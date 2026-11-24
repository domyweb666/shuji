// 測試用：不走 API 金鑰，改叫這台電腦上的 claude CLI（用 Claude 訂閱的登入）。
// 只給 eval、本機測試和電腦轉接（bridge/）用。Cloudflare Workers 不能啟動外部程式，正式路徑一律走 src/model.ts 的 anthropicCaller。
//
// 跟正式版的差別：沒有提示快取、沒有 Sonnet 的伺服器端備援、沒有 max_tokens 上限；
// 輸出格式不是 API 強制的，而是在系統提示最後多加一段格式要求，再用同一份 schema 驗。
// 系統提示的其他部分、輸出 schema、模型、effort 都跟正式版同一份來源。
import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import * as z from 'zod/v4';
import { systemBlocks, type ModelCaller, type ModelResult } from '../src/model';
import { OUTPUTS, TASKS, type TaskId } from '../src/tasks';

const TIMEOUT_MS = 180_000;

/** 找出要執行的程式。Windows 的 claude 是 npm 的 .cmd 包裝，中文參數經過 cmd 會壞，所以直接用 node 跑 cli.js。 */
export function resolveCli(): { cmd: string; pre: string[] } {
  const override = process.env.SHUJI_CLAUDE_CLI;
  if (override) return override.endsWith('.js') ? { cmd: process.execPath, pre: [override] } : { cmd: override, pre: [] };
  if (process.platform === 'win32') {
    for (const dir of (process.env.PATH ?? '').split(delimiter)) {
      if (!dir || !existsSync(join(dir, 'claude.cmd'))) continue;
      const js = join(dir, 'node_modules', '@anthropic-ai', 'claude-code', 'cli.js');
      if (existsSync(js)) return { cmd: process.execPath, pre: [js] };
    }
    throw new Error('找不到 claude CLI 的 cli.js。用 SHUJI_CLAUDE_CLI 指定路徑。');
  }
  return { cmd: 'claude', pre: [] };
}

/** 不把外層的 Claude／Anthropic 環境變數帶進去：在 Claude Code 裡跑 eval 時，繼承來的設定會蓋掉 CLI 自己的登入；也避免不小心用到 API 金鑰計費。 */
function cleanEnv(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (/^(CLAUDE|ANTHROPIC)/i.test(k)) continue;
    env[k] = v;
  }
  return env;
}

interface CliResult {
  is_error?: boolean;
  result?: string;
  structured_output?: unknown;
  stop_reason?: string | null;
  usage?: { input_tokens?: number; output_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number };
}

// CLI 的 --json-schema 在換掉系統提示、關掉工具之後不會生效（2.1.81 實測，模型直接回文字），
// 所以格式改用提示要求，回來再用同一份 zod schema 驗。
function formatNote(task: TaskId): string {
  return `輸出格式：只輸出一個 JSON 物件，不要用程式碼區塊包起來，前後不要有任何其他文字。必須符合這份 JSON Schema，每個欄位都要出現：\n${JSON.stringify(z.toJSONSchema(OUTPUTS[task]))}`;
}

/** 正式版的結構化輸出保證每個欄位都在；CLI 沒有這層保證，模型常把「沒有」的欄位整個省略。可以是 null 的最上層欄位缺了就補 null，其他照原樣交給 schema 驗。 */
function fillNulls(task: TaskId, value: unknown): unknown {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return value;
  const out: Record<string, unknown> = { ...(value as Record<string, unknown>) };
  for (const [key, field] of Object.entries(OUTPUTS[task].shape as Record<string, z.ZodType>)) {
    if (!(key in out) && field.safeParse(null).success) out[key] = null;
  }
  return out;
}

/** 從 CLI 的 JSON 結果取出任務輸出。純函式，測試用得到。 */
export function parseCliResult<T extends TaskId>(task: T, stdout: string): ModelResult<z.infer<(typeof OUTPUTS)[T]>> {
  const text = stdout.trim();
  let res: CliResult;
  try {
    res = JSON.parse(text) as CliResult;
  } catch {
    throw new Error(`CLI 回的不是 JSON：${text.slice(0, 200)}`);
  }
  if (res.is_error) {
    const msg = String(res.result ?? '');
    if (/authenticat|OAuth|login/i.test(msg)) throw new Error('claude CLI 的登入過期了。在終端機跑 claude，輸入 /login 重新登入後再試。');
    throw new Error(`CLI 回報錯誤：${msg.slice(0, 300)}`);
  }
  let candidate: unknown = res.structured_output;
  if (candidate === undefined || candidate === null) {
    // 舊版 CLI 沒有 structured_output 欄位，JSON 會在 result 字串裡（可能包在 ```json 區塊）
    const raw = String(res.result ?? '').replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
    try {
      candidate = JSON.parse(raw);
    } catch {
      candidate = null;
    }
  }
  const parsed = candidate === null ? null : OUTPUTS[task].safeParse(fillNulls(task, candidate));
  const u = res.usage ?? {};
  return {
    parsed: (parsed && parsed.success ? parsed.data : null) as any,
    stopReason: parsed && !parsed.success ? 'schema_mismatch' : (res.stop_reason ?? null),
    usage: {
      input: u.input_tokens ?? 0,
      output: u.output_tokens ?? 0,
      cacheRead: u.cache_read_input_tokens ?? 0,
      cacheWrite: u.cache_creation_input_tokens ?? 0,
    },
  };
}

export interface CliOptions {
  /** 給 CLI 的環境變數。不給就是拿掉 CLAUDE／ANTHROPIC 開頭的那些 */
  env?: NodeJS.ProcessEnv;
  /** 這一次最多還能跑多久 */
  timeoutMs?: () => number;
  /** 使用者的內容交給 CLI 之前再洗一次 */
  clean?: (text: string) => string;
  /** 工作資料夾（預設開一個空的） */
  work?: string;
  /** 系統提示檔放哪（預設跟工作資料夾同一個） */
  promptDir?: string;
  model?: string;
  onChild?: (child: ChildProcess | null) => void;
  kill?: (child: ChildProcess) => void;
}

export function cliCaller(options: CliOptions = {}): ModelCaller {
  const { cmd, pre } = resolveCli();
  const env = options.env ?? cleanEnv();
  // 空資料夾當工作目錄，CLI 才不會讀到任何專案的 CLAUDE.md
  const work = options.work ?? mkdtempSync(join(tmpdir(), 'shuji-eval-'));
  const promptDir = options.promptDir ?? work;
  const promptFiles = new Map<TaskId, string>();
  const promptFile = (task: TaskId) => {
    let f = promptFiles.get(task);
    if (!f) {
      f = join(promptDir, `system-${task}.txt`);
      writeFileSync(f, [...systemBlocks(task).map((b) => b.text), formatNote(task)].join('\n\n'), 'utf8');
      promptFiles.set(task, f);
    }
    return f;
  };

  return (task, input) => {
    const spec = TASKS[task];
    const args = [
      ...pre,
      '-p',
      '--model', options.model || spec.model,
      '--effort', spec.effort,
      '--tools', '',
      '--setting-sources', '',
      '--strict-mcp-config',
      '--disable-slash-commands',
      '--no-session-persistence',
      '--system-prompt-file', promptFile(task),
      '--output-format', 'json',
    ];
    return new Promise((resolve, reject) => {
      const timeout = options.timeoutMs ? options.timeoutMs() : TIMEOUT_MS;
      if (timeout <= 0) return reject(new Error('時間用完了'));
      const child = spawn(cmd, args, { cwd: work, env, windowsHide: true });
      options.onChild?.(child);
      let out = '';
      let err = '';
      const timer = setTimeout(() => {
        if (options.kill) options.kill(child);
        else child.kill();
        reject(new Error(`CLI 超過 ${Math.round(timeout / 1000)} 秒沒回應`));
      }, timeout);
      child.stdout.setEncoding('utf8').on('data', (d) => (out += d));
      child.stderr.setEncoding('utf8').on('data', (d) => (err += d));
      child.stdin.on('error', () => {
        /* CLI 先結束時 stdin 會斷，交給 close 處理 */
      });
      child.on('error', (e) => {
        clearTimeout(timer);
        options.onChild?.(null);
        reject(new Error(`啟動 claude CLI 失敗：${e.message}`));
      });
      child.on('close', (code) => {
        clearTimeout(timer);
        options.onChild?.(null);
        if (process.env.SHUJI_CLI_DEBUG === '1') console.error(`\n[cli 任務 ${task}] ${out.slice(0, 3000)}`);
        if (!out.trim()) return reject(new Error(`CLI 沒有輸出（結束碼 ${code}）：${err.slice(0, 300)}`));
        try {
          resolve(parseCliResult(task, out));
        } catch (e) {
          reject(e as Error);
        }
      });
      const text = JSON.stringify(input);
      child.stdin.end(options.clean ? options.clean(text) : text, 'utf8');
    });
  };
}
