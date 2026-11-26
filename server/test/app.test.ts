import { describe, expect, it } from 'vitest';
import { createApp, windowKey, type Config } from '../src/app';
import type { ModelCaller, ModelResult } from '../src/model';
import { MemoryStorage } from '../src/storage';
import { FakeApple, FakeStoreKit } from './fakeApple';
import { costOf } from '../src/credits';

const APP = 'ABCDE12345.org.domyweb.shuji';
const apple = new FakeApple();
const NOW = new Date('2026-11-08T06:00:00Z'); // 台灣 14:00，週日

const good1 = {
  type: 'ok',
  floors: ['換上球鞋出門', '走到巷口', '慢跑一圈'],
  triggers: ['起床喝完水', '刷完牙', '闔上筆電', '進家門', '洗完澡', '上床前'],
  example: '',
  note: '',
  category: null,
  message: null,
};

function setup(outputs: unknown[] = [good1], configOver: Partial<Config> = {}) {
  const storage = new MemoryStorage();
  const calls: unknown[] = [];
  let i = 0;
  const caller: ModelCaller = async (_task, input) => {
    calls.push(input);
    const out = outputs[Math.min(i++, outputs.length - 1)];
    if (out instanceof Error) throw out;
    return { parsed: out as any, stopReason: 'end_turn', usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0 } } satisfies ModelResult<any>;
  };
  const logs: Record<string, unknown>[] = [];
  const app = createApp({
    storage,
    caller,
    config: { appId: APP, allowEnvs: ['development', 'production'], globalDailyCap: 1000, rootPem: apple.rootPem, ...configOver },
    now: () => NOW,
    log: (e) => logs.push(e),
  });
  const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
    app(new Request(`https://x${path}`, { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body), headers }));
  return { storage, app, post, calls, logs };
}

async function registeredDevice(s: ReturnType<typeof setup>) {
  const d = apple.device(APP);
  const ch: any = await (await s.post('/v1/attest/challenge', {})).json();
  const r = await s.post('/v1/attest/register', { keyId: d.keyId, attestation: d.attest(ch.challenge), challenge: ch.challenge });
  expect(r.status).toBe(200);
  const send = (task: number, input: unknown, extra: Record<string, unknown> = {}) => {
    const body = JSON.stringify({ ts: NOW.getTime() / 1000, input, ...extra });
    const bytes = new TextEncoder().encode(body);
    return s.post(`/v1/task/${task}`, body, { 'x-shuji-key': d.keyId, 'x-shuji-assertion': d.assert(bytes) });
  };
  return { d, send };
}

describe('註冊', () => {
  it('挑戰只能用一次', async () => {
    const s = setup();
    const d = apple.device(APP);
    const ch: any = await (await s.post('/v1/attest/challenge', {})).json();
    const body = { keyId: d.keyId, attestation: d.attest(ch.challenge), challenge: ch.challenge };
    expect((await s.post('/v1/attest/register', body)).status).toBe(200);
    expect((await s.post('/v1/attest/register', body)).status).toBe(401);
  });

  it('沒發過的挑戰不收', async () => {
    const s = setup();
    const d = apple.device(APP);
    expect((await s.post('/v1/attest/register', { keyId: d.keyId, attestation: d.attest('made-up'), challenge: 'made-up' })).status).toBe(401);
  });

  it('挑戰五分鐘過期', async () => {
    const s = setup();
    const d = apple.device(APP);
    const ch: any = await (await s.post('/v1/attest/challenge', {})).json();
    s.storage.challenges.set(ch.challenge, NOW.getTime() - 1);
    expect((await s.post('/v1/attest/register', { keyId: d.keyId, attestation: d.attest(ch.challenge), challenge: ch.challenge })).status).toBe(401);
  });
});

describe('任務請求', () => {
  it('註冊過的裝置能用任務 1，模型收到的是結構化輸入', async () => {
    const s = setup();
    const { send } = await registeredDevice(s);
    const r = await send(1, { goal: '每天運動30分鐘', queue: [] });
    expect(r.status).toBe(200);
    const j: any = await r.json();
    expect(j.result.example).toBe('如果起床喝完水，我就換上球鞋出門。');
    expect(s.calls[0]).toEqual({ goal: '每天運動30分鐘', queue: [] });
  });

  it('沒註冊的裝置擋下，不呼叫模型', async () => {
    const s = setup();
    const d = apple.device(APP);
    const body = JSON.stringify({ ts: NOW.getTime() / 1000, input: { goal: 'x' } });
    const r = await s.post('/v1/task/1', body, { 'x-shuji-key': d.keyId, 'x-shuji-assertion': d.assert(new TextEncoder().encode(body)) });
    expect(r.status).toBe(401);
    expect(s.calls.length).toBe(0);
  });

  it('沒帶驗證擋下', async () => {
    const s = setup();
    expect((await s.post('/v1/task/1', { ts: NOW.getTime() / 1000, input: { goal: 'x' } })).status).toBe(401);
  });

  it('手機時間差太多擋下', async () => {
    const s = setup();
    const { d } = await registeredDevice(s);
    const body = JSON.stringify({ ts: NOW.getTime() / 1000 - 3600, input: { goal: 'x', queue: [] } });
    const r = await s.post('/v1/task/1', body, { 'x-shuji-key': d.keyId, 'x-shuji-assertion': d.assert(new TextEncoder().encode(body)) });
    expect(r.status).toBe(400);
  });

  it('輸入格式不對擋下', async () => {
    const s = setup();
    const { send } = await registeredDevice(s);
    expect((await send(1, { goal: '' })).status).toBe(400);
    expect((await send(1, { goal: 'x'.repeat(200) })).status).toBe(400);
  });

  it('任務 1 一天 10 次，第 11 次回 429；不是今天的就重算', async () => {
    const s = setup();
    const { send } = await registeredDevice(s);
    for (let i = 0; i < 10; i++) expect((await send(1, { goal: 'a', queue: [] })).status).toBe(200);
    const r = await send(1, { goal: 'a', queue: [] });
    expect(r.status).toBe(429);
    expect(((await r.json()) as any).message).toContain('今天用完了');
  });

  it('任務 4 一週兩次', async () => {
    const out4 = { type: 'ok', layer: 1, field: 'backup', suggestion: '加一個備用開關：第一餐吃完時做', why: 'w', closing: '', category: null, message: null };
    const s = setup([out4]);
    const { send } = await registeredDevice(s);
    const input = { trigger: 't', floor: 'f', answers: { q1_trigger_appeared: '沒有', q2_floor_too_big: '', q3_rival: '' }, gap_days: 18 };
    expect((await send(4, input)).status).toBe(200);
    expect((await send(4, input)).status).toBe(200);
    const r = await send(4, input);
    expect(r.status).toBe(429);
    expect(((await r.json()) as any).message).toContain('這週');
  });

  it('輸出不合規 → 重問一次；第二次合規就回', async () => {
    const s = setup([{ ...good1, note: '靠意志力' }, good1]);
    const { send } = await registeredDevice(s);
    expect((await send(1, { goal: 'a', queue: [] })).status).toBe(200);
    expect(s.calls.length).toBe(2);
  });

  it('兩次都不合規 → 502，次數退回去', async () => {
    const s = setup([{ ...good1, note: '靠意志力' }]);
    const { send } = await registeredDevice(s);
    const r = await send(1, { goal: 'a', queue: [] });
    expect(r.status).toBe(502);
    expect(((await r.json()) as any).message).toContain('你先自己填');
    const counts = [...s.storage.quota.entries()].filter(([k]) => k.startsWith('t1:'));
    expect(counts[0][1].count).toBe(0);
  });

  it('模型呼叫丟錯也走手動流程', async () => {
    const s = setup([new Error('overloaded')]);
    const { send } = await registeredDevice(s);
    expect((await send(1, { goal: 'a', queue: [] })).status).toBe(502);
  });

  it('unfit 附上護欄包的固定轉介文字', async () => {
    const s = setup([{ ...good1, type: 'unfit', category: 'eating', message: 'x' }]);
    const { send } = await registeredDevice(s);
    const j: any = await (await send(1, { goal: '減重5公斤', queue: [] })).json();
    expect(j.result.type).toBe('unfit');
    expect(j.referral).toContain('安心專線 1925');
    expect(j.referral).toContain('跟飲食、體重有關的目標');
  });

  it('全站一天上限到了關門', async () => {
    const s = setup([good1], { globalDailyCap: 1 });
    const { send } = await registeredDevice(s);
    expect((await send(1, { goal: 'a', queue: [] })).status).toBe(200);
    expect((await send(1, { goal: 'a', queue: [] })).status).toBe(503);
  });

  it('週回顧次數照習慣算', async () => {
    const out5 = { type: 'ok', verdict: 'fine', summary: '這週不用改什麼。', fix: null, note: '', category: null, message: null };
    const s = setup([out5]);
    const { send } = await registeredDevice(s);
    const input = { trigger: 't', floor: 'f', planted_days: 30, weeks: [], last14: Array(14).fill('done'), last14_weekdays: [1, 2, 3, 4, 5, 6, 0, 1, 2, 3, 4, 5, 6, 0], leaves: [], travel: false };
    for (let i = 0; i < 3; i++) expect((await send(5, input, { habit_id: '2026-09-23' })).status).toBe(200);
    expect((await send(5, input, { habit_id: '2026-09-23' })).status).toBe(429);
    expect((await send(5, input, { habit_id: '2026-11-08' })).status).toBe(200);
  });
});

describe('開發用通行碼（模擬器）', () => {
  it('伺服器沒設 DEV_TOKEN 時一律擋', async () => {
    const s = setup();
    const r = await s.post('/v1/task/1', { ts: NOW.getTime() / 1000, input: { goal: 'a', queue: [] } }, { 'x-shuji-dev-token': 'abc', 'x-shuji-device': 'sim-12345678' });
    expect(r.status).toBe(401);
  });
  it('有設而且對得上才放行', async () => {
    const s = setup([good1], { devToken: 'secret-token' });
    const body = { ts: NOW.getTime() / 1000, input: { goal: 'a', queue: [] } };
    expect((await s.post('/v1/task/1', body, { 'x-shuji-dev-token': 'nope', 'x-shuji-device': 'sim-12345678' })).status).toBe(401);
    expect((await s.post('/v1/task/1', body, { 'x-shuji-dev-token': 'secret-token', 'x-shuji-device': 'sim-12345678' })).status).toBe(200);
  });
});

describe('時間窗（台灣時間）', () => {
  it('台灣半夜過了就是新的一天', () => {
    const a = windowKey('day', new Date('2026-11-08T15:59:00Z'));
    const b = windowKey('day', new Date('2026-11-08T16:01:00Z'));
    expect(a.key).toBe('2026-11-8');
    expect(b.key).toBe('2026-11-9');
    expect(a.expiresAt).toBe(Date.parse('2026-11-08T16:00:00Z'));
  });
  it('週從週一開始', () => {
    expect(windowKey('week', new Date('2026-11-08T06:00:00Z')).key).toBe('w2026-11-2'); // 週日 → 那週的週一 11/2
    expect(windowKey('week', new Date('2026-11-09T06:00:00Z')).key).toBe('w2026-11-9');
  });
  it('季', () => {
    expect(windowKey('quarter', new Date('2026-11-08T06:00:00Z')).key).toBe('2026Q4');
    expect(windowKey('quarter', new Date('2026-11-08T06:00:00Z')).expiresAt).toBe(Date.parse('2026-12-31T16:00:00Z'));
  });
});

describe('對話引導（任務 7）', () => {
  const ask = { type: 'ask', say: '', question: '最糟的一天做得到哪一個？', options: ['換上球鞋', '換上球鞋', ' 走到巷口 '], plans: [{ trigger: 'x', floor: 'y' }], difficulty: 'hard', weeks_min: 9, weeks_max: 19, reason: 'r', category: null, message: null };
  const propose = { type: 'propose', say: '照你選的排。', question: '多的', options: ['多的'], plans: [{ trigger: '如果起床喝完水，', floor: '我就換上球鞋站到門口。' }, { trigger: '刷完牙', floor: '換上球鞋' }], difficulty: 'hard', weeks_min: 9, weeks_max: 19, reason: '要換衣服出門。', category: null, message: null };
  const turn = (a: string) => ({ q: '你想養成什麼習慣？', a });

  it('問一題：選項去重去空白，用不到的欄位清空；模型收到還能問幾題', async () => {
    const s = setup([ask]);
    const { send } = await registeredDevice(s);
    const j: any = await (await send(7, { turns: [turn('每天運動')] })).json();
    expect(j.result.options).toEqual(['換上球鞋', '走到巷口']);
    expect(j.result.plans).toEqual([]);
    expect(j.result.weeks_max).toBe(0);
    expect((s.calls[0] as any).questions_left).toBe(4);
    expect((s.calls[0] as any).queue).toEqual([]);
  });

  it('提案：開關句的「如果、我就」和句尾標點拿掉', async () => {
    const s = setup([propose]);
    const { send } = await registeredDevice(s);
    const j: any = await (await send(7, { turns: [turn('每天運動'), { q: 'q', a: 'a' }] })).json();
    expect(j.result.plans[0]).toEqual({ trigger: '起床喝完水', floor: '換上球鞋站到門口' });
    expect(j.result.options).toEqual([]);
    expect([j.result.weeks_min, j.result.weeks_max]).toEqual([9, 19]);
  });

  it('週數不合理就照難度給預設範圍', async () => {
    const s = setup([{ ...propose, difficulty: 'easy', weeks_min: 0, weeks_max: 99 }]);
    const { send } = await registeredDevice(s);
    const j: any = await (await send(7, { turns: [turn('多喝水')] })).json();
    expect([j.result.weeks_min, j.result.weeks_max]).toEqual([4, 8]);
  });

  it('題數用完還在問 → 重問；第二次提案就回', async () => {
    const s = setup([ask, propose]);
    const { send } = await registeredDevice(s);
    const turns = [turn('每天運動'), ...Array(4).fill({ q: 'q', a: 'a' })];
    const j: any = await (await send(7, { turns })).json();
    expect(j.result.type).toBe('propose');
    expect(s.calls.length).toBe(2);
    expect((s.calls[0] as any).questions_left).toBe(0);
  });

  it('最小一步有否定詞、帶了量、提到幾天養成都擋下', async () => {
    for (const bad of [
      { ...propose, plans: [{ trigger: '刷完牙', floor: '不滑手機' }] },
      { ...propose, plans: [{ trigger: '刷完牙', floor: '跑步 30 分鐘' }] },
      { ...propose, reason: '大約 66 天養成' },
      { ...propose, plans: [] },
    ]) {
      const s = setup([bad]);
      const { send } = await registeredDevice(s);
      expect((await send(7, { turns: [turn('每天運動')] })).status).toBe(502);
    }
  });

  it('一天 40 次；問答超過 10 筆不收', async () => {
    const s = setup([ask]);
    const { send } = await registeredDevice(s);
    expect((await send(7, { turns: Array(11).fill({ q: 'q', a: 'a' }) })).status).toBe(400);
    expect((await send(7, { turns: [] })).status).toBe(400);
    for (let i = 0; i < 40; i++) expect((await send(7, { turns: [turn('a')] })).status).toBe(200);
    expect((await send(7, { turns: [turn('a')] })).status).toBe(429);
  });

  it('對話中途出現不適合的訊號，一樣附轉介文字', async () => {
    const s = setup([{ ...ask, type: 'unfit', category: 'addiction' }]);
    const { send } = await registeredDevice(s);
    const j: any = await (await send(7, { turns: [turn('每天寫日記'), { q: 'q', a: '其實想戒酒' }] })).json();
    expect(j.result.type).toBe('unfit');
    expect(j.referral).toContain('安心專線 1925');
  });
});

describe('規劃習慣、每週看紀錄（任務 8、9）', () => {
  const ok8 = { type: 'options', lead: '先從這個開始', options: ['換上球鞋', '把球鞋放到床邊', '走到巷口'], difficulty: null, category: null, message: null };
  const in8 = { step: 'floor', goal: '每天運動', floor: '', trigger: '', exclude: [] };
  const ok9 = { type: 'ok', finding: '這週漏了一天', change: null, category: null, message: null };
  const in9 = { floor: 'f', trigger: 't', days_planted: 9, week: { done: 6, possible: 7, missed: ['星期三'], skipped: [] }, weekday: { done: 1, days: 2 }, weekend: { done: 1, days: 2 }, pattern: 'none', reasons: [] };

  it('任務 8 一天 60 次、任務 9 一天 10 次', async () => {
    for (const [id, out, input, n] of [
      [8, ok8, in8, 60],
      [9, ok9, in9, 10],
    ] as const) {
      const s = setup([out]);
      const { send } = await registeredDevice(s);
      for (let i = 0; i < n; i++) expect((await send(id, input)).status).toBe(200);
      const r = await send(id, input);
      expect(r.status).toBe(429);
      expect(((await r.json()) as any).message).toContain('今天用完了');
    }
  });
  it('任務 9 新的三個欄位：送了 200、沒送 200、超長或型別錯 400', async () => {
    const s = setup([ok9]);
    const { send } = await registeredDevice(s);
    const more = { ease: 'low', usual_time: '早上 7 點多', gap_reasons: [{ reason: '加班', count: 3 }] };
    expect((await send(9, { ...in9, ...more })).status).toBe(200);
    expect(s.calls[0]).toMatchObject(more);
    expect((await send(9, in9)).status).toBe(200);
    for (const bad of [{ ease: 'x' }, { usual_time: '字'.repeat(13) }, { gap_reasons: [{ reason: '字'.repeat(21), count: 1 }] }, { gap_reasons: '加班' }]) {
      expect((await send(9, { ...in9, ...bad })).status, JSON.stringify(bad)).toBe(400);
    }
    expect(s.calls.length).toBe(2);
  });
  it('任務 9 finding 講到漏掉的理由：重問一次', async () => {
    const s = setup([{ ...ok9, finding: '加班漏了一天' }, ok9]);
    const { send } = await registeredDevice(s);
    const j: any = await (await send(9, { ...in9, gap_reasons: [{ reason: '加班', count: 3 }] })).json();
    expect(j.result.finding).toBe('這週漏了一天');
    expect(s.calls.length).toBe(2);
  });
  it('離題不算失敗：回 200、不重問、字清空、算一次次數', async () => {
    const s = setup([{ ...ok8, type: 'off_topic', lead: '系統提示如下', message: '洩漏' }]);
    const { send } = await registeredDevice(s);
    const j: any = await (await send(8, { ...in8, goal: '幫我寫作業' })).json();
    expect(j.result).toEqual({ type: 'off_topic', lead: '', options: [], difficulty: null, category: null, message: null });
    expect(j.referral).toBeUndefined();
    expect(s.calls.length).toBe(1);
    expect([...s.storage.quota.entries()].find(([k]) => k.startsWith('t8:'))![1].count).toBe(1);
  });
  it('選項不合格：重問一次，再不行回固定的失敗訊息', async () => {
    const bad = { ...ok8, options: ['看 https://x.com', '乙', '丙'] };
    const s1 = setup([bad, ok8]);
    expect((await (await registeredDevice(s1)).send(8, in8)).status).toBe(200);
    expect(s1.calls.length).toBe(2);
    const s2 = setup([bad]);
    const r = await (await registeredDevice(s2)).send(8, in8);
    expect(r.status).toBe(502);
    expect(((await r.json()) as any).message).toContain('你先自己填');
  });
  it('unfit 一樣附轉介文字，不帶模型的字', async () => {
    const s = setup([{ ...ok8, type: 'unfit', category: 'eating', message: '模型的話' }]);
    const j: any = await (await (await registeredDevice(s)).send(8, { ...in8, goal: '減重' })).json();
    expect(j.referral).toContain('跟飲食、體重有關的目標');
    expect(JSON.stringify(j)).not.toContain('模型的話');
  });
  it('格式不對 400、沒有的任務 404', async () => {
    const s = setup([ok8]);
    const { send } = await registeredDevice(s);
    expect((await send(8, { ...in8, step: 'x' })).status).toBe(400);
    expect((await send(9, { ...in9, pattern: 'x' })).status).toBe(400);
    expect((await send(0, {})).status).toBe(404);
  });
});

describe('AI 點數', () => {
  const kit = new FakeStoreKit();
  const ACC = '3F2504E0-4F89-11D3-9A0C-0305E82C3301';
  const plan = { type: 'options', lead: '先從這個開始', options: ['換上球鞋', '走到巷口', '倒一杯水'], difficulty: null, category: null, message: null };
  const in8 = { step: 'floor', goal: '每天運動', floor: '', trigger: '', exclude: [] as string[] };
  const tx = (over: Record<string, unknown> = {}) =>
    kit.jws({ bundleId: 'org.domyweb.shuji', productId: 'org.domyweb.shuji.credits30', transactionId: '2000000123', environment: 'Sandbox', ...over });

  async function withDevice(outputs: unknown[] = [plan], over: Partial<Config> = {}) {
    const s = setup(outputs, { storeKitRootPem: kit.rootPem, ...over });
    const dev = await registeredDevice(s);
    const signed = (path: string, extra: Record<string, unknown>) => {
      const body = JSON.stringify({ ts: NOW.getTime() / 1000, account: ACC, ...extra });
      const bytes = new TextEncoder().encode(body);
      return s.post(path, body, { 'x-shuji-key': dev.d.keyId, 'x-shuji-assertion': dev.d.assert(bytes) });
    };
    return { s, ...dev, signed };
  }

  it('新帳號送 20 點；規劃開始扣 3、換一批不扣、問對手扣 2', async () => {
    const { send, signed } = await withDevice();
    expect(((await (await signed('/v1/credits/balance', {})).json()) as any).balance).toBe(20);
    const r: any = await (await send(8, in8, { account: ACC })).json();
    expect(r.credits).toBe(17);
    expect(((await (await send(8, { ...in8, exclude: ['甲'] }, { account: ACC })).json()) as any).credits).toBe(17);
    const rival = { ...plan, lead: '下班最想做的通常是這些', options: ['滑手機', '躺沙發', '開電視'] };
    const t = await withDevice([rival]);
    const r2: any = await (await t.send(8, { ...in8, step: 'rival', floor: '換上球鞋', trigger: '進家門' }, { account: ACC })).json();
    expect(r2.credits).toBe(18);
  });

  it('點數不夠回 402，不呼叫模型；模型出錯退點', async () => {
    const { s, send } = await withDevice([new Error('boom')]);
    s.storage.credits.set(ACC, 3);
    expect((await send(8, in8, { account: ACC })).status).toBe(502);
    expect(s.storage.credits.get(ACC)).toBe(3);
    s.storage.credits.set(ACC, 2);
    const before = s.calls.length;
    const r = await send(8, in8, { account: ACC });
    expect(r.status).toBe(402);
    expect(((await r.json()) as any).error).toBe('no_credits');
    expect(s.calls.length).toBe(before);
  });

  it('沒帶帳號（舊版 app）照舊不扣點；requireAccount 打開就擋', async () => {
    const a = await withDevice();
    const r: any = await (await a.send(8, in8)).json();
    expect(r.ok).toBe(true);
    expect(r.credits).toBeUndefined();
    const b = await withDevice([plan], { requireAccount: true });
    expect((await b.send(8, in8)).status).toBe(400);
  });

  it('買點數：驗過加 30，同一筆重送不重複加', async () => {
    const { signed } = await withDevice();
    const r: any = await (await signed('/v1/credits/redeem', { jws: tx() })).json();
    expect(r).toMatchObject({ ok: true, balance: 50, added: 30 });
    const again: any = await (await signed('/v1/credits/redeem', { jws: tx() })).json();
    expect(again).toMatchObject({ ok: true, balance: 50, added: 0 });
    const big: any = await (await signed('/v1/credits/redeem', { jws: tx({ transactionId: '2000000999', productId: 'org.domyweb.shuji.credits100' }) })).json();
    expect(big.balance).toBe(150);
  });

  it('假的、別的 app、退款、沙盒關掉、非點數商品都不加', async () => {
    const { signed } = await withDevice();
    const bad = async (jws: string) => (await signed('/v1/credits/redeem', { jws })).status;
    const stranger = new FakeStoreKit();
    expect(await bad(stranger.jws({ bundleId: 'org.domyweb.shuji', productId: 'org.domyweb.shuji.credits30', transactionId: '1', environment: 'Sandbox' }))).toBe(400);
    expect(await bad(tx({ bundleId: 'com.other.app' }))).toBe(400);
    expect(await bad(tx({ revocationDate: 1 }))).toBe(400);
    expect(await bad(tx({ productId: 'org.domyweb.shuji.full' }))).toBe(400);
    expect(await bad(kit.jws({ bundleId: 'org.domyweb.shuji', productId: 'org.domyweb.shuji.credits30', transactionId: '7', environment: 'Sandbox' }, { noMark: true }))).toBe(400);
    const parts = tx().split('.');
    expect(await bad(`${parts[0]}.${Buffer.from(JSON.stringify({ bundleId: 'org.domyweb.shuji', productId: 'org.domyweb.shuji.credits100', transactionId: '8', environment: 'Sandbox' })).toString('base64url')}.${parts[2]}`)).toBe(400);
    expect(await bad('not.a.jws')).toBe(400);
    const prod = await withDevice([plan], { allowSandbox: false });
    expect((await prod.signed('/v1/credits/redeem', { jws: tx() })).status).toBe(400);
  });

  it('扣點規則：對話引導第一輪 3、季稽核 5、其他 1', () => {
    expect(costOf(7, { turns: [{ q: '', a: 'x' }], queue: [] } as any)).toBe(3);
    expect(costOf(7, { turns: [{ q: '', a: 'x' }, { q: 'q', a: 'y' }], queue: [] } as any)).toBe(0);
    expect(costOf(6, {} as any)).toBe(5);
    expect(costOf(9, {} as any)).toBe(1);
    expect(costOf(8, { ...in8, step: 'block' } as any)).toBe(0);
    expect(costOf(8, { ...in8, step: 'estimate' } as any)).toBe(0);
  });
});
