import { AttestError, b64, verifyAssertion, verifyAttestation, type AttestEnv, type RegisteredKey } from './attest/appattest';
import { referralFor, review } from './checks';
import type { ModelCaller } from './model';
import type { Storage } from './storage';
import { INPUTS, TASKS, isTaskId, type TaskId, type Window } from './tasks';

// 中繼伺服器的請求處理，不依賴 Cloudflare，測試直接呼叫。
//
// POST /v1/attest/challenge   → { challenge }                         發一次性挑戰（五分鐘）
// POST /v1/attest/register    { keyId, attestation, challenge }        驗 App Attest，存公鑰
// POST /v1/task/{1-6}         { ts, habit_id?, input }                 header 帶 x-shuji-key、x-shuji-assertion
//                                                                      （assertion 簽的是整個 body 的原始位元組）
// 回應一律 JSON：{ ok: true, task, result, referral? } 或 { ok: false, error, message }

export interface Config {
  appId: string;
  allowEnvs: AttestEnv[];
  /** 有設才接受開發用 token（模擬器沒有 App Attest）。正式環境不要設 */
  devToken?: string;
  /** 全部裝置加起來一天最多幾次模型呼叫，超過就關門，防被灌爆 */
  globalDailyCap: number;
  /** 測試用：換掉 Apple 根憑證 */
  rootPem?: string;
}

export interface Deps {
  storage: Storage;
  caller: ModelCaller;
  config: Config;
  now?: () => Date;
  log?: (entry: Record<string, unknown>) => void;
}

const MAX_BODY = 8 * 1024;
const TS_SKEW = 5 * 60;

const WINDOW_LIMIT_MSG: Record<Window, string> = {
  day: '今天用完了，明天再來。你先自己填就好。',
  week: '這週用完了，下週再來。你先自己改就好。',
  habit: '這個習慣的週回顧建議用完了。',
  quarter: '這一季的稽核用完了。',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

const fail = (status: number, error: string, message: string) => json(status, { ok: false, error, message });

// ---------- 時間窗（台灣時間） ----------

const TPE = 8 * 3600 * 1000;

export function windowKey(w: Window, now: Date, habitId?: string): { key: string; expiresAt: number } {
  const t = new Date(now.getTime() + TPE); // 用 UTC 欄位讀，就是台灣時間
  const y = t.getUTCFullYear();
  const m = t.getUTCMonth();
  const d = t.getUTCDate();
  const midnightUtc = (yy: number, mm: number, dd: number) => Date.UTC(yy, mm, dd) - TPE;
  switch (w) {
    case 'day':
      return { key: `${y}-${m + 1}-${d}`, expiresAt: midnightUtc(y, m, d + 1) };
    case 'week': {
      const dow = (t.getUTCDay() + 6) % 7; // 週一 = 0
      const monday = new Date(Date.UTC(y, m, d - dow));
      return {
        key: `w${monday.getUTCFullYear()}-${monday.getUTCMonth() + 1}-${monday.getUTCDate()}`,
        expiresAt: midnightUtc(monday.getUTCFullYear(), monday.getUTCMonth(), monday.getUTCDate() + 7),
      };
    }
    case 'quarter': {
      const q = Math.floor(m / 3);
      return { key: `${y}Q${q + 1}`, expiresAt: midnightUtc(y, q * 3 + 3, 1) };
    }
    case 'habit':
      return { key: `h${habitId ?? 'none'}`, expiresAt: now.getTime() + 400 * 86400 * 1000 };
  }
}

function randomChallenge(): string {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return b64.encode(b).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function readBody(req: Request): Promise<Uint8Array | null> {
  const buf = new Uint8Array(await req.arrayBuffer());
  return buf.length > MAX_BODY ? null : buf;
}

function parseJson(bytes: Uint8Array): any {
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return undefined;
  }
}

export function createApp(deps: Deps) {
  const now = deps.now ?? (() => new Date());
  const log = deps.log ?? ((e) => console.log(JSON.stringify(e)));
  const { storage, config } = deps;

  async function challenge(req: Request): Promise<Response> {
    const ip = req.headers.get('cf-connecting-ip') ?? 'unknown';
    const n = now();
    const w = windowKey('day', n);
    if ((await storage.incr(`ch:${ip}:${w.key}`, w.expiresAt, n.getTime())) > 50) return fail(429, 'rate_limited', '太多次了，等一下再試。');
    const c = randomChallenge();
    await storage.putChallenge(c, n.getTime() + 5 * 60 * 1000);
    return json(200, { ok: true, challenge: c });
  }

  async function register(req: Request): Promise<Response> {
    const bytes = await readBody(req);
    const body = bytes && parseJson(bytes);
    if (!body || typeof body.keyId !== 'string' || typeof body.attestation !== 'string' || typeof body.challenge !== 'string') {
      return fail(400, 'bad_request', '格式不對。');
    }
    const n = now();
    if (!(await storage.takeChallenge(body.challenge, n.getTime()))) return fail(401, 'attest_failed', '挑戰過期了，重來一次。');
    try {
      const key = await verifyAttestation(body.keyId, body.attestation, body.challenge, {
        appId: config.appId,
        allowEnvs: config.allowEnvs,
        now: n,
        rootPem: config.rootPem,
      });
      await storage.putKey(key, n.getTime());
      log({ ev: 'register', env: key.env });
      return json(200, { ok: true });
    } catch (e) {
      log({ ev: 'register_fail', reason: (e as Error).message });
      return fail(401, 'attest_failed', '這台裝置驗證不過。');
    }
  }

  /** 認出是哪台裝置。回傳用來算次數的裝置代號，或錯誤回應 */
  async function authenticate(req: Request, body: Uint8Array): Promise<{ device: string } | Response> {
    const dev = req.headers.get('x-shuji-dev-token');
    if (dev !== null) {
      const device = req.headers.get('x-shuji-device') ?? '';
      if (!config.devToken || dev !== config.devToken || !/^[A-Za-z0-9-]{8,64}$/.test(device)) {
        return fail(401, 'attest_failed', '開發用通行碼不對。');
      }
      return { device: `dev:${device}` };
    }
    const keyId = req.headers.get('x-shuji-key');
    const assertion = req.headers.get('x-shuji-assertion');
    if (!keyId || !assertion) return fail(401, 'attest_failed', '缺少裝置驗證。');
    const key: RegisteredKey | null = await storage.getKey(keyId);
    if (!key) return fail(401, 'not_registered', '這台裝置還沒註冊。');
    try {
      const counter = await verifyAssertion(key, assertion, body, config.appId);
      if (!(await storage.bumpCounter(keyId, counter))) throw new AttestError('計數器被搶先更新（重放？）');
    } catch (e) {
      log({ ev: 'assert_fail', reason: (e as Error).message });
      return fail(401, 'attest_failed', '這台裝置驗證不過。');
    }
    return { device: keyId };
  }

  async function task(req: Request, id: TaskId): Promise<Response> {
    const bytes = await readBody(req);
    if (!bytes) return fail(413, 'bad_request', '內容太長了。');
    const who = await authenticate(req, bytes);
    if (who instanceof Response) return who;

    const body = parseJson(bytes);
    const n = now();
    if (!body || typeof body.ts !== 'number' || Math.abs(n.getTime() / 1000 - body.ts) > TS_SKEW) {
      return fail(400, 'bad_request', '手機的時間跟伺服器差太多。');
    }
    const parsed = INPUTS[id].safeParse(body.input);
    if (!parsed.success) return fail(400, 'bad_request', '輸入格式不對。');
    const habitId = typeof body.habit_id === 'string' ? body.habit_id.slice(0, 32) : undefined;

    // 次數：全站先擋，再擋這台裝置
    const spec = TASKS[id];
    const day = windowKey('day', n);
    if ((await storage.incr(`global:${day.key}`, day.expiresAt, n.getTime())) > config.globalDailyCap) {
      return fail(503, 'unavailable', '現在想不出來，你先自己填，等一下再試。');
    }
    const w = windowKey(spec.quota.window, n, habitId);
    const bucket = `t${id}:${who.device}:${w.key}`;
    if ((await storage.incr(bucket, w.expiresAt, n.getTime())) > spec.quota.limit) {
      await storage.decr(`global:${day.key}`);
      return fail(429, 'rate_limited', WINDOW_LIMIT_MSG[spec.quota.window]);
    }

    // 問模型：不合規就再問一次，再不行回手動流程，次數退回去
    let problems: string[] = [];
    for (let attempt = 1; attempt <= 2; attempt++) {
      let r;
      try {
        r = await deps.caller(id, parsed.data);
      } catch (e) {
        problems = [`呼叫失敗：${(e as Error).message}`];
        log({ ev: 'model_error', task: id, attempt, reason: (e as Error).message });
        continue;
      }
      if (!r.parsed || r.stopReason === 'refusal' || r.stopReason === 'max_tokens') {
        problems = [`沒有可用的輸出（${r.stopReason}）`];
        log({ ev: 'model_empty', task: id, attempt, stop: r.stopReason, usage: r.usage });
        continue;
      }
      const checked = review(id, r.parsed as any);
      log({ ev: 'model_ok', task: id, attempt, pass: checked.ok, problems: checked.problems, usage: r.usage });
      if (!checked.ok) {
        problems = checked.problems;
        continue;
      }
      const result = checked.value as any;
      return json(200, {
        ok: true,
        task: id,
        result,
        ...(result.type === 'unfit' ? { referral: referralFor(result.category) } : {}),
      });
    }
    await storage.decr(bucket);
    await storage.decr(`global:${day.key}`);
    log({ ev: 'bad_output', task: id, problems });
    return fail(502, 'bad_output', '現在想不出來，你先自己填，等一下再試。');
  }

  return async function handle(req: Request): Promise<Response> {
    const url = new URL(req.url);
    if (req.method === 'GET' && url.pathname === '/v1/health') return json(200, { ok: true });
    if (req.method !== 'POST') return fail(405, 'bad_request', '只收 POST。');
    if (url.pathname === '/v1/attest/challenge') return challenge(req);
    if (url.pathname === '/v1/attest/register') return register(req);
    const m = url.pathname.match(/^\/v1\/task\/(\d)$/);
    if (m && isTaskId(Number(m[1]))) return task(req, Number(m[1]) as TaskId);
    return fail(404, 'bad_request', '沒有這個路徑。');
  };
}
