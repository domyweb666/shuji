import * as z from 'zod/v4';
import { PACKS, INSTRUCTIONS } from './generated/packs';

// 六個任務的規格，照 ai/提示詞與輸出格式.md 與 ai/AI交接.md。
// 輸出 schema 裡「有時候沒有」的欄位一律用 null，不用省略：結構化輸出要每個欄位都在。

export type TaskId = 1 | 2 | 3 | 4 | 5 | 6;
export const TASK_IDS: TaskId[] = [1, 2, 3, 4, 5, 6];

const short = (n = 60) => z.string().trim().min(1).max(n);
const shortOrEmpty = (n = 200) => z.string().trim().max(n);

export const UNFIT = z.enum(['addiction', 'compulsion', 'bfrb', 'eating', 'mood']);
export const FIELD = z.enum(['trigger', 'floor', 'backup', 'obstacle', 'travelFloor']);

/** 每個任務都可能回 unfit：category 與 message 兩欄每個 schema 都有 */
const unfitFields = {
  category: UNFIT.nullable(),
  message: z.string().nullable(),
};

// ---------- 輸入（app 送來的結構化資料，長度都設上限） ----------

export const INPUTS = {
  1: z.object({
    goal: short(80),
    queue: z.array(short(40)).max(10).default([]),
  }),
  2: z.object({
    trigger: short(40),
    floor: short(40),
    interruptions: shortOrEmpty(300),
    travels: z.boolean(),
  }),
  3: z.object({
    trigger: short(40),
    floor: short(40),
    rival: short(200),
    feel: shortOrEmpty(100),
  }),
  4: z.object({
    trigger: short(40),
    floor: short(40),
    answers: z.object({
      q1_trigger_appeared: shortOrEmpty(200),
      q2_floor_too_big: shortOrEmpty(200),
      q3_rival: shortOrEmpty(200),
    }),
    gap_days: z.number().int().min(0).max(3650),
  }),
  5: z.object({
    trigger: short(40),
    floor: short(40),
    planted_days: z.number().int().min(0).max(36500),
    weeks: z.array(z.object({ date: z.string().max(10), avg: z.number().min(1).max(7) })).max(26),
    last14: z.array(z.enum(['done', 'miss', 'leave'])).length(14),
    last14_weekdays: z.array(z.number().int().min(0).max(6)).length(14),
    leaves: z.array(z.object({ date: z.string().max(10), reason: shortOrEmpty(60) })).max(20),
    travel: z.boolean(),
  }),
  6: z.object({
    floor: short(40),
    trigger: short(40),
    why: shortOrEmpty(100),
    status: z.enum(['growing', 'dug']),
    quarter: z.object({
      done_rate: z.number().min(0).max(1),
      weekly_avg: z.array(z.number().min(1).max(7)).max(20),
      leaves: z.number().int().min(0).max(366),
      returns: z.number().int().min(0).max(366),
    }),
    user: z.object({
      satisfied: shortOrEmpty(300),
      context_change: shortOrEmpty(300),
    }),
  }),
} as const;

// ---------- 輸出（給模型的結構化輸出 schema） ----------

export const OUTPUTS = {
  1: z.object({
    type: z.enum(['ok', 'needs_rewrite', 'too_rare', 'unfit']),
    floors: z.array(z.string()),
    triggers: z.array(z.string()),
    example: z.string(),
    note: z.string(),
    ...unfitFields,
  }),
  2: z.object({
    type: z.enum(['ok', 'unfit']),
    obstacles: z.array(z.object({ if: z.string(), then: z.string() })),
    backup: z.string().nullable(),
    travel: z.object({ portable: z.boolean(), floor: z.string(), alt: z.string() }).nullable(),
    note: z.string(),
    ...unfitFields,
  }),
  3: z.object({
    type: z.enum(['ok', 'unfit']),
    rival_type: z.enum(['temptation', 'autopilot', 'internal', 'social']).nullable(),
    block: z.string(),
    clear: z.string(),
    note: z.string(),
    ...unfitFields,
  }),
  4: z.object({
    type: z.enum(['ok', 'unfit']),
    layer: z.union([z.literal(0), z.literal(1), z.literal(4), z.literal(6)]),
    field: FIELD.nullable(),
    suggestion: z.string(),
    why: z.string(),
    closing: z.string(),
    ...unfitFields,
  }),
  5: z.object({
    type: z.enum(['ok', 'unfit']),
    verdict: z.enum(['fine', 'fix']),
    summary: z.string(),
    fix: z.object({ field: FIELD.nullable(), suggestion: z.string() }).nullable(),
    note: z.string(),
    ...unfitFields,
  }),
  6: z.object({
    type: z.enum(['ok', 'unfit']),
    path: z.enum(['keep', 'scale', 'relocate', 'retire']),
    change: z.string(),
    why: z.string(),
    warn: z.string(),
    ...unfitFields,
  }),
} as const;

export type TaskInput<T extends TaskId> = z.infer<(typeof INPUTS)[T]>;
export type TaskOutput<T extends TaskId> = z.infer<(typeof OUTPUTS)[T]>;

// ---------- 模型、知識包、次數上限 ----------

export type Window = 'day' | 'week' | 'quarter' | 'habit';

export interface TaskSpec {
  id: TaskId;
  name: string;
  model: 'claude-haiku-5-5' | 'claude-sonnet-5-5';
  effort: 'low' | 'medium';
  maxTokens: number;
  pack: keyof typeof PACKS;
  /** 付費功能：伺服器只擋次數，付費由 app 用 StoreKit 判斷 */
  paid: boolean;
  quota: { limit: number; window: Window };
}

export const TASKS: Record<TaskId, TaskSpec> = {
  1: { id: 1, name: '種下去助手', model: 'claude-haiku-5-5', effort: 'low', maxTokens: 4096, pack: 'build', paid: false, quota: { limit: 10, window: 'day' } },
  2: { id: 2, name: '障礙版與旅行版', model: 'claude-haiku-5-5', effort: 'low', maxTokens: 4096, pack: 'obstacle', paid: false, quota: { limit: 5, window: 'day' } },
  3: { id: 3, name: '對手偵測', model: 'claude-haiku-5-5', effort: 'low', maxTokens: 4096, pack: 'obstacle', paid: false, quota: { limit: 3, window: 'day' } },
  4: { id: 4, name: '三問診斷', model: 'claude-haiku-5-5', effort: 'low', maxTokens: 4096, pack: 'diagnose', paid: false, quota: { limit: 2, window: 'week' } },
  5: { id: 5, name: '週回顧建議', model: 'claude-haiku-5-5', effort: 'low', maxTokens: 4096, pack: 'diagnose', paid: true, quota: { limit: 3, window: 'habit' } },
  6: { id: 6, name: '季稽核', model: 'claude-sonnet-5-5', effort: 'medium', maxTokens: 8192, pack: 'audit', paid: true, quota: { limit: 2, window: 'quarter' } },
};

export function instructionFor(id: TaskId): string {
  return INSTRUCTIONS[id];
}

export function isTaskId(n: number): n is TaskId {
  return (TASK_IDS as number[]).includes(n);
}
