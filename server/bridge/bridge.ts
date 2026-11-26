// 電腦轉接：iPhone 上的薯記把 AI 任務送到這台電腦，這裡組好提示、交給你登入的 claude CLI，檢查完再回給手機。
// 組提示、檢查輸出、回傳的 body 都跟正式伺服器（src/）同一份程式，app 只要一套解碼。
// 擋的東西照蘿蔔旅行的 ios/tools/claude-bridge：隨機密碼、一次一句、逾時、環境變數白名單、半形 @ 換全形、空資料夾。
import { execFileSync, spawn, type ChildProcess } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { cliCaller, resolveCli } from '../eval/cliCaller';
import { BAD_OUTPUT_MSG, askModel } from '../src/app';
import type { ModelCaller } from '../src/model';
import { INPUTS, isTaskId, type TaskId } from '../src/tasks';

export const BODY_MAX = 8 * 1024;
/** 一句（含重問一次）最多跑多久。app 那頭等 180 秒，這裡要先放棄 */
export const TIMEOUT_MS = 170_000;
/** 同時只跑一句，後面最多再排這麼多句 */
export const WAIT_MAX = 2;
const IS_WIN = process.platform === 'win32';

// ---------- 交給 CLI 的東西 ----------

// 只帶 CLI 跑得起來、找得到登入、連得出去要的；各家 API 金鑰、外層 Claude Code 的設定都不給
const ENV_KEEP = new Set(
  (
    'PATH PATHEXT SYSTEMROOT SYSTEMDRIVE WINDIR COMSPEC OS PROCESSOR_ARCHITECTURE PROGRAMDATA PROGRAMFILES PROGRAMFILES(X86) PROGRAMW6432 ' +
    'HOME USERPROFILE HOMEDRIVE HOMEPATH APPDATA LOCALAPPDATA USER USERNAME LOGNAME SHELL TEMP TMP TMPDIR LANG LC_ALL LC_CTYPE TZ ' +
    'XDG_CONFIG_HOME XDG_DATA_HOME HTTP_PROXY HTTPS_PROXY NO_PROXY NODE_EXTRA_CA_CERTS NODE_USE_SYSTEM_CA ' +
    'CLAUDE_CODE_GIT_BASH_PATH'
  ).split(' '),
);

export function childEnv(source: NodeJS.ProcessEnv = process.env): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const [k, v] of Object.entries(source)) if (ENV_KEEP.has(k.toUpperCase())) env[k] = v;
  // CLI 自己的設定：不處理 `@路徑` 附檔、不載 CLAUDE.md、不載自動記憶、不附 git 狀態
  env.CLAUDE_CODE_DISABLE_ATTACHMENTS = '1';
  env.CLAUDE_CODE_DISABLE_CLAUDE_MDS = '1';
  env.CLAUDE_CODE_DISABLE_AUTO_MEMORY = '1';
  env.CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = '1';
  return env;
}

/** CLI 看到 `@檔案` 會自己把檔附進去。送進去的是一段 JSON，開頭一定是 {，所以只要換掉 @ */
export function cleanInput(text: string): string {
  return text.replace(/@/g, '＠');
}

function killTree(child: ChildProcess | null) {
  if (!child || child.exitCode !== null || child.killed) return;
  if (IS_WIN && child.pid) {
    try {
      execFileSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true });
      return;
    } catch {
      /* 退回下面 */
    }
  }
  child.kill('SIGKILL');
}

export function cliVersion(): Promise<string> {
  return new Promise((resolve) => {
    let out = '';
    let child: ChildProcess;
    try {
      const { cmd, pre } = resolveCli();
      child = spawn(cmd, [...pre, '--version'], { env: childEnv(), windowsHide: true });
    } catch {
      return resolve('');
    }
    const timer = setTimeout(() => (killTree(child), resolve('')), 20_000);
    child.stdout?.on('data', (d) => (out += d));
    child.on('error', () => (clearTimeout(timer), resolve('')));
    child.on('close', (code) => (clearTimeout(timer), resolve(code === 0 ? out.trim() : '')));
    child.stdin?.end();
  });
}

// ---------- HTTP ----------

export interface BridgeOptions {
  token?: string;
  name?: string;
  cli?: string;
  timeoutMs?: number;
  /** 測試用：換掉叫 CLI 的那一段 */
  caller?: ModelCaller;
  print?: (line: string) => void;
}

const stamp = () => new Date().toLocaleTimeString('zh-TW', { hour12: false });

export function createBridge(options: BridgeOptions = {}) {
  const token = options.token ?? crypto.randomBytes(16).toString('hex');
  const print = options.print ?? ((line: string) => console.log(`[${stamp()}] ${line}`));
  const limit = options.timeoutMs ?? TIMEOUT_MS;
  const name = options.name ?? os.hostname();

  // 工作資料夾永遠是空的；系統提示檔放隔壁。關掉時兩個一起刪
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'shuji-claude-bridge-'));
  const work = path.join(home, 'work');
  const promptDir = path.join(home, 'prompt');
  fs.mkdirSync(work);
  fs.mkdirSync(promptDir);

  let running: ChildProcess | null = null;
  let deadline = 0;
  const caller =
    options.caller ??
    cliCaller({
      env: childEnv(),
      work,
      promptDir,
      clean: cleanInput,
      model: (process.env.CLAUDE_MODEL || '').trim() || undefined,
      timeoutMs: () => deadline - Date.now(),
      onChild: (c) => (running = c),
      kill: killTree,
    });

  let queue: Promise<unknown> = Promise.resolve();
  let waiting = 0;
  let busy = false;
  function enqueue<T>(task: () => Promise<T>): Promise<T> {
    waiting += 1;
    const go = () => {
      waiting -= 1;
      busy = true;
      return task().finally(() => (busy = false));
    };
    const p = queue.then(go, go);
    queue = p.catch(() => {});
    return p;
  }

  function send(res: http.ServerResponse, code: number, obj: unknown) {
    if (res.writableEnded || res.destroyed) return;
    const body = JSON.stringify(obj);
    res.writeHead(code, {
      'content-type': 'application/json; charset=utf-8',
      'content-length': Buffer.byteLength(body),
      'cache-control': 'no-store',
    });
    res.end(body);
  }
  const fail = (res: http.ServerResponse, code: number, error: string, message: string) => send(res, code, { ok: false, error, message });

  function tokenOk(t: string | null) {
    // 先 sha256 再比：兩邊一定都是 32 位元組，送什麼字來都不會丟例外
    const hash = (s: string) => crypto.createHash('sha256').update(s, 'utf8').digest();
    return t !== null && crypto.timingSafeEqual(hash(t), hash(token));
  }

  async function task(res: http.ServerResponse, id: TaskId, raw: Buffer) {
    let body: any;
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch {
      /* 下面一起擋 */
    }
    if (!body || typeof body !== 'object') return fail(res, 400, 'bad_request', '格式不對。');
    const parsed = INPUTS[id].safeParse(body.input);
    if (!parsed.success) return fail(res, 400, 'bad_request', '輸入格式不對。');
    if (waiting >= WAIT_MAX) return fail(res, 429, 'rate_limited', '電腦還在想前面那幾句，等一下再試。');
    const ahead = waiting + (busy ? 1 : 0);
    print(`收到任務 ${id}（${raw.length} 位元組）${ahead ? `，前面還有 ${ahead} 句` : ''}`);
    // 手機那頭關掉畫面或放棄了：還沒回就斷線，就不用再想。
    // 只有輪到這一句、CLI 正在跑的時候才殺（同時只跑一句，這時的 running 一定是這一句的）；還在排隊的只記下來，輪到時跳過
    let gone = false;
    let mine = false;
    res.on('close', () => {
      if (res.writableEnded) return;
      gone = true;
      if (mine && running) {
        print(`任務 ${id}：手機斷線，停掉這一句的 CLI`);
        killTree(running);
      }
    });
    await enqueue(async () => {
      // 排隊時 app 那頭已經放棄了，就不用再跑
      if (gone || res.destroyed) return print(`任務 ${id}：手機已經斷線，沒跑`);
      const t0 = Date.now();
      deadline = t0 + limit;
      // CLI 的原話可能有這台電腦的路徑：只印在這個終端機，手機那頭只拿到固定的一句
      const log = (e: Record<string, unknown>) => {
        if (e.ev === 'model_error') print(`CLI 說：${String(e.reason).slice(0, 200)}`);
        else if (e.ev === 'model_empty') print(`第 ${e.attempt} 次沒有可用的輸出（${e.stop}）`);
        else if (e.ev === 'model_ok' && !e.pass) {
          print(`第 ${e.attempt} 次不合規：${(e.problems as string[]).map((p) => p.split(/[：（]/)[0]).join('、')}`);
        }
      };
      let a: Awaited<ReturnType<typeof askModel>>;
      mine = true;
      try {
        // 斷線時 CLI 被殺會丟錯，askModel 接住後看到 stop 就不重問，這一句結束、排隊往下走
        a = await askModel(caller, id, parsed.data, log, () => gone || res.destroyed || Date.now() >= deadline);
      } finally {
        mine = false;
      }
      if (gone) return print(`任務 ${id}：手機已經斷線，不回了`);
      const sec = ((Date.now() - t0) / 1000).toFixed(1);
      if (a.ok) {
        print(`任務 ${id} 回了，花 ${sec} 秒`);
        return send(res, 200, a.body);
      }
      print(`任務 ${id} 沒成功，花 ${sec} 秒`);
      if (a.problems.some((p) => p.includes('登入過期'))) {
        return fail(res, 502, 'cli_login', '電腦上的 Claude 登入過期了，在電腦的終端機跑 claude 重新登入。');
      }
      if (Date.now() >= deadline) return fail(res, 504, 'timeout', '電腦想太久了，等一下再試一次。');
      fail(res, 502, 'bad_output', BAD_OUTPUT_MSG);
    });
  }

  function handle(req: http.IncomingMessage, res: http.ServerResponse) {
    let url: URL;
    try {
      url = new URL(req.url || '/', 'http://localhost');
    } catch {
      return fail(res, 400, 'bad_request', '網址看不懂。');
    }
    if (!tokenOk(url.searchParams.get('t'))) {
      req.resume();
      return fail(res, 401, 'bad_token', '電腦重開過，密碼換了。再掃一次電腦上的 QR code。');
    }
    if (url.pathname === '/ping') {
      req.resume();
      if (req.method !== 'GET') return fail(res, 405, 'bad_request', '只收 GET。');
      return send(res, 200, { ok: true, name, cli: options.cli ?? '' });
    }
    const m = url.pathname.match(/^\/v1\/task\/(\d)$/);
    if (!m || !isTaskId(Number(m[1]))) {
      req.resume();
      return fail(res, 404, 'bad_request', '沒有這個路徑。');
    }
    if (req.method !== 'POST') {
      req.resume();
      return fail(res, 405, 'bad_request', '只收 POST。');
    }
    const chunks: Buffer[] = [];
    let size = 0;
    let tooBig = false;
    req.on('data', (d: Buffer) => {
      if (tooBig) return;
      size += d.length;
      if (size > BODY_MAX) {
        tooBig = true;
        fail(res, 413, 'bad_request', '內容太長了。');
        return;
      }
      chunks.push(d);
    });
    req.on('end', () => {
      if (!tooBig) task(res, Number(m[1]) as TaskId, Buffer.concat(chunks)).catch((e) => oops(res, e));
    });
    req.on('error', () => {
      /* 連線斷掉就算了 */
    });
  }

  function oops(res: http.ServerResponse, e: unknown) {
    print(`出錯了：${e instanceof Error ? e.stack : e}`);
    try {
      fail(res, 500, 'unavailable', '電腦那頭出錯了，等一下再試。');
    } catch {
      res.destroy();
    }
  }

  const server = http.createServer((req, res) => {
    try {
      handle(req, res);
    } catch (e) {
      oops(res, e);
    }
  });
  // 「把請求整個送完」的時限，不算 CLI 跑的時間
  server.requestTimeout = 60_000;
  server.headersTimeout = 30_000;

  function dispose() {
    killTree(running);
    try {
      fs.rmSync(home, { recursive: true, force: true });
    } catch {
      /* 刪不掉就留給系統清 */
    }
  }

  return { server, token, dispose, work };
}
