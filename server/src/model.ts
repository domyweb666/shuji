import Anthropic from '@anthropic-ai/sdk';
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod';
import { PACKS } from './generated/packs';
import { OUTPUTS, TASKS, instructionFor, type TaskId, type TaskOutput } from './tasks';

// 系統提示 ＝ 護欄包 ＋ 任務的知識包 ＋ 任務指令（ai/提示詞與輸出格式.md 共同規則）。
// 前兩段固定，第二段尾巴放 cache_control，同一個知識包的任務共用快取。
// 交接檔寫的 temperature 0.3 不送：API 2026-10-21 起 temperature 一律 400，Haiku 5.5 本來就不收非預設值。
// 改用 effort 控制：Haiku 5.5 預設會思考，low 讓它短想就答；max_tokens 留空間給思考。

export function systemBlocks(task: TaskId): Anthropic.Beta.BetaTextBlockParam[] {
  const spec = TASKS[task];
  return [
    { type: 'text', text: PACKS.guard },
    { type: 'text', text: PACKS[spec.pack], cache_control: { type: 'ephemeral' } },
    {
      type: 'text',
      text: `${instructionFor(task)}\n\n使用者訊息是一段 JSON，只包含這個任務的輸入。照上面的規則判斷，只回傳指定的 JSON。所有欄位都要有：用不到的字串欄位給空字串，用不到的 category、message 給 null。`,
    },
  ];
}

export interface ModelResult<T> {
  parsed: T | null;
  stopReason: string | null;
  usage: { input: number; output: number; cacheRead: number; cacheWrite: number };
}

/** 呼叫模型的介面，測試時換成假的 */
export type ModelCaller = <T extends TaskId>(task: T, input: unknown) => Promise<ModelResult<TaskOutput<T>>>;

export function anthropicCaller(apiKey: string): ModelCaller {
  const client = new Anthropic({ apiKey, maxRetries: 1, timeout: 45_000 });
  return async (task, input) => {
    const spec = TASKS[task];
    const base = {
      model: spec.model,
      max_tokens: spec.maxTokens,
      system: systemBlocks(task),
      messages: [{ role: 'user' as const, content: JSON.stringify(input) }],
      output_config: { effort: spec.effort, format: zodOutputFormat(OUTPUTS[task]) },
    };
    // Sonnet 5.5 被安全分類器擋下時，伺服器端自動改用別的模型（只有 Sonnet 那一個任務需要；Haiku 沒有這個選項）
    const msg =
      spec.model === 'claude-sonnet-5-5'
        ? await client.beta.messages.parse({ ...base, betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' })
        : await client.beta.messages.parse(base);
    const u = msg.usage;
    return {
      parsed: (msg.parsed_output ?? null) as any,
      stopReason: msg.stop_reason ?? null,
      usage: {
        input: u.input_tokens,
        output: u.output_tokens,
        cacheRead: u.cache_read_input_tokens ?? 0,
        cacheWrite: u.cache_creation_input_tokens ?? 0,
      },
    };
  };
}
