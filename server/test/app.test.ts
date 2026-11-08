import { describe, expect, it } from 'vitest';
import { createApp, windowKey, type Config } from '../src/app';
import type { ModelCaller, ModelResult } from '../src/model';
import { MemoryStorage } from '../src/storage';
import { FakeApple } from './fakeApple';

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
