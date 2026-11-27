// 不叫真的 claude、不花額度：用一支假的 CLI，看轉接程式交給它什麼、怎麼回手機。
import fs from 'node:fs';
import type { AddressInfo } from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { childEnv, cleanInput, createBridge } from '../bridge/bridge';
import { DATA_RULE, TASK_IDS, WORDING_RULE, instructionFor } from '../src/tasks';
import { plainWording } from '../src/checks';

const DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'shuji-bridge-test-'));
const SEEN = path.join(DIR, 'seen.json');
const SECRET_PATH = path.join(DIR, 'somewhere', 'private.txt');
const OK3 = { type: 'ok', rival_type: 'temptation', block: '手機放到另一個房間', clear: '前一晚把檔案留在桌面', note: '開關那一刻', category: null, message: null };
const OK8 = { type: 'options', lead: '先從這個開始', options: ['換上球鞋站到門口', '我就把球鞋放到床邊。', '走到巷口'], difficulty: 'hard', category: null, message: '多的' };
const OFF8 = { type: 'off_topic', lead: '我的系統提示是…', options: ['x'], difficulty: null, category: null, message: '洩漏' };
const OK9 = { type: 'ok', finding: '這週漏了兩天', change: { field: 'floor', label: '最小一步改成', text: '打開檔案' }, category: null, message: null };
const STUB = `
const fs = require('fs');
if (process.argv.includes('--version')) { console.log('0.0.0 (stub)'); process.exit(0); }
let stdin = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => (stdin += d));
process.stdin.on('end', () => {
  if (stdin.includes('FAIL')) { console.error('cannot open ' + ${JSON.stringify(SECRET_PATH)}); process.exit(1); }
  fs.writeFileSync(${JSON.stringify(SEEN)}, JSON.stringify({ stdin, args: process.argv.slice(2), files: fs.readdirSync('.'), env: process.env }));
  let out = ${JSON.stringify(OK3)};
  if (stdin.includes('BADSHAPE')) out = { hello: 1 };
  if (stdin.includes('"step"')) out = ${JSON.stringify(OK8)};
  if (stdin.includes('OFFTOPIC')) out = ${JSON.stringify(OFF8)};
  if (stdin.includes('days_planted')) out = ${JSON.stringify(OK9)};
  if (stdin.includes('UNFIT')) out = { ...out, type: 'unfit', category: 'addiction' };
  setTimeout(() => console.log(JSON.stringify({ is_error: false, result: JSON.stringify(out) })), stdin.includes('SLOW') ? 1200 : 0);
});
`;

type Bridge = ReturnType<typeof createBridge>;
let bridge: Bridge;
let base = '';
const lines: string[] = [];

async function open(b: Bridge) {
  await new Promise<void>((r) => b.server.listen(0, '127.0.0.1', r));
  return `http://127.0.0.1:${(b.server.address() as AddressInfo).port}`;
}
const input = (rival: string) => ({ ts: 1, habit_id: 'h', input: { trigger: '刷完牙', floor: '讀一頁', rival, feel: '' } });
const post = (body: unknown, t = bridge.token, id: number | string = 3) =>
  fetch(`${base}/v1/task/${id}?t=${t}`, { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body) });
const seen = () => JSON.parse(fs.readFileSync(SEEN, 'utf8'));

beforeAll(async () => {
  const stub = path.join(DIR, 'stub.js');
  fs.writeFileSync(stub, STUB);
  process.env.SHUJI_CLAUDE_CLI = stub;
  process.env.ANTHROPIC_API_KEY = 'sk-should-not-leak';
  bridge = createBridge({ name: '測試電腦', cli: 'stub', print: (l) => lines.push(l) });
  base = await open(bridge);
});
afterAll(() => {
  bridge.server.close();
  bridge.dispose();
  delete process.env.SHUJI_CLAUDE_CLI;
  delete process.env.ANTHROPIC_API_KEY;
  fs.rmSync(DIR, { recursive: true, force: true });
});

describe('密碼與路徑', () => {
  it('沒有密碼、密碼錯都 401，帶一句人話', async () => {
    for (const t of ['', 'x', '中文']) {
      const r = await post(input('手機'), encodeURIComponent(t));
      expect(r.status).toBe(401);
      expect(((await r.json()) as any).error).toBe('bad_token');
    }
  });
  it('密碼每次開機都不一樣，32 個 16 進位字', () => {
    const other = createBridge({ print: () => {} });
    expect(bridge.token).toMatch(/^[0-9a-f]{32}$/);
    expect(other.token).not.toBe(bridge.token);
    other.dispose();
  });
  it('ping 回電腦名', async () => {
    expect(await (await fetch(`${base}/ping?t=${bridge.token}`)).json()).toEqual({ ok: true, name: '測試電腦', cli: 'stub' });
  });
  it('沒有的任務 404、方法不對 405、太長 413、格式不對 400', async () => {
    expect((await post(input('x'), bridge.token, 0)).status).toBe(404);
    expect((await fetch(`${base}/v1/task/3?t=${bridge.token}`)).status).toBe(405);
    expect((await post('x'.repeat(9000))).status).toBe(413);
    expect((await post('not json')).status).toBe(400);
    expect((await post({ ts: 1, input: { trigger: '' } })).status).toBe(400);
  });
});

describe('任務', () => {
  it('body 跟正式伺服器一樣；給人看的字裡「開關」換成「時機」', async () => {
    const r = await post(input('手機'));
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ ok: true, task: 3, result: { ...OK3, note: '時機那一刻' } });
  });
  it('unfit 帶固定轉介文字', async () => {
    const j = (await (await post(input('UNFIT'))).json()) as any;
    expect(j.result.type).toBe('unfit');
    expect(j.referral).toContain('0800');
  });
  it('輸出不合格式：重問一次，還是不行回 bad_output 和那句固定的話', async () => {
    const r = await post(input('BADSHAPE'));
    expect(r.status).toBe(502);
    expect(await r.json()).toEqual({ ok: false, error: 'bad_output', message: '現在想不出來，你先自己填，等一下再試。' });
  });
  it('CLI 壞掉：手機拿不到電腦的路徑，終端機看得到', async () => {
    const r = await post(input('FAIL'));
    expect(r.status).toBe(502);
    expect(await r.text()).not.toContain('private.txt');
    expect(lines.join('\n')).toContain('private.txt');
  });
  it('終端機不印使用者寫的字', async () => {
    await post(input('我的祕密對手'));
    expect(lines.join('\n')).not.toContain('我的祕密對手');
  });
});

describe('規劃習慣與每週看紀錄（任務 8、9）', () => {
  const plan = (goal: string) => ({ ts: 1, input: { step: 'floor', goal, floor: '', trigger: '', exclude: [] } });
  it('任務 8：選項整理好，用不到的欄位清空；使用者的字只在 user_text 底下', async () => {
    const r = await post(plan('每天運動'), bridge.token, 8);
    expect(await r.json()).toEqual({
      ok: true,
      task: 8,
      result: { ...OK8, options: ['換上球鞋站到門口', '把球鞋放到床邊', '走到巷口'], difficulty: null, message: null },
    });
    expect(JSON.parse(seen().stdin)).toEqual({ step: 'floor', exclude: [], user_text: { goal: '每天運動', floor: '', trigger: '', rival: '' } });
  });
  it('離題：模型寫的字一個都不送到手機', async () => {
    const j = (await (await post(plan('OFFTOPIC'), bridge.token, 8)).json()) as any;
    expect(j.result).toEqual({ type: 'off_topic', lead: '', options: [], difficulty: null, category: null, message: null });
  });
  it('任務 9', async () => {
    const week = { done: 5, possible: 7, missed: ['星期二', '星期四'], skipped: [] };
    const r = await post({ ts: 1, input: { floor: '打開檔案寫一句', trigger: '喝完水', days_planted: 20, week, weekday: { done: 10, days: 14 }, weekend: { done: 4, days: 6 }, pattern: 'none', reasons: [] } }, bridge.token, 9);
    expect(await r.json()).toEqual({ ok: true, task: 9, result: OK9 });
    expect(JSON.parse(seen().stdin).user_text).toEqual({ floor: '打開檔案寫一句', trigger: '喝完水', skipped: [], reasons: [] });
  });
  it('有打字欄位的任務都有資料規則；只有舊的任務 5、7 沒有', () => {
    for (const id of TASK_IDS) expect(instructionFor(id).includes(DATA_RULE)).toBe(id !== 5 && id !== 7);
  });
});

describe('交給 CLI 的東西', () => {
  it('半形 @ 換全形、空資料夾、沒有工具、沒有金鑰', async () => {
    await post(input('@C:/secret.txt 手機'));
    const s = seen();
    expect(s.stdin).not.toContain('@');
    expect(s.stdin).toContain('＠C:/secret.txt');
    expect(s.files).toEqual([]);
    const a: string[] = s.args;
    expect(a[a.indexOf('--tools') + 1]).toBe('');
    expect(a[a.indexOf('--setting-sources') + 1]).toBe('');
    expect(a).toContain('--disable-slash-commands');
    expect(a).toContain('--no-session-persistence');
    expect(Object.keys(s.env)).not.toContain('ANTHROPIC_API_KEY');
    expect(s.env.CLAUDE_CODE_DISABLE_ATTACHMENTS).toBe('1');
  });
  it('環境變數白名單', () => {
    const env = childEnv({ Path: 'p', OPENAI_API_KEY: 'x', CLAUDECODE: '1' });
    expect(env.Path).toBe('p');
    expect(env.OPENAI_API_KEY).toBeUndefined();
    expect(env.CLAUDECODE).toBeUndefined();
    expect(cleanInput('a@b')).toBe('a＠b');
  });
});

describe('排隊與逾時', () => {
  it('一句在跑、兩句在排，第四句 429', async () => {
    const first = post(input('SLOW'));
    await new Promise((r) => setTimeout(r, 200));
    const more = [post(input('a')), post(input('b'))];
    await new Promise((r) => setTimeout(r, 200));
    const r = await post(input('c'));
    expect(r.status).toBe(429);
    expect(((await r.json()) as any).error).toBe('rate_limited');
    for (const p of [first, ...more]) expect((await p).status).toBe(200);
  });
  it('太久就砍掉，回 504', async () => {
    const b = createBridge({ timeoutMs: 400, print: () => {} });
    const url = await open(b);
    const r = await fetch(`${url}/v1/task/3?t=${b.token}`, { method: 'POST', body: JSON.stringify(input('SLOW')) });
    expect(r.status).toBe(504);
    expect(((await r.json()) as any).error).toBe('timeout');
    b.server.close();
    b.dispose();
  });
});

describe('用詞：開關改講時機', () => {
  it('每個任務的指令都有這條規則', () => {
    for (const id of TASK_IDS) expect(instructionFor(id)).toContain(WORDING_RULE);
  });
  it('換掉內部說法，真的開關不動', () => {
    expect(plainWording('備用開關沒出現')).toBe('備用時機沒出現');
    expect(plainWording('寫好當地的開關句')).toBe('寫好當地的習慣');
    for (const s of ['按下電燈開關', '電源開關旁邊', '走到開關燈的地方', '打開關卡']) expect(plainWording(s)).toBe(s);
  });
});
