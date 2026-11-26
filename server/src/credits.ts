import { b64 } from './attest/appattest';
import { ab, parseCertificate, pemToDer, verifySignedBy } from './attest/x509';
import type { TaskId, TaskInput } from './tasks';

// AI 點數（多米 2026-11-26 定：習慣格子買斷＋AI 點數，docs/規劃-點數收費-多習慣-AI對手與犒賞-2026-11-26.md 第一節）。
// 點數記在伺服器，對到 app 產生的匿名帳號（存在 iCloud 鑰匙圈，換手機也在）。
// 用自己電腦的 Claude（bridge/）不經過這裡，不扣點。

/** 新帳號送的點數 */
export const FREE_CREDITS = 20;

/** 消耗型內購商品 → 加幾點。App Store Connect 要建一樣的 Product ID */
export const CREDIT_PRODUCTS: Record<string, number> = {
  'org.domyweb.shuji.credits30': 30,
  'org.domyweb.shuji.credits100': 100,
};

/**
 * 這次呼叫扣幾點。照「一件事」算，不照呼叫次數：
 * - 規劃一個習慣：開始問最小一步那次扣 3，問對手那次扣 2；換一批、後面幾步都不扣
 * - 對話引導：第一輪扣 3
 * - 季稽核 5，其他每次 1
 */
export function costOf(id: TaskId, input: unknown): number {
  switch (id) {
    case 8: {
      const i = input as TaskInput<8>;
      if (i.exclude.length > 0) return 0;
      if (i.step === 'floor') return 3;
      if (i.step === 'rival') return 2;
      return 0;
    }
    case 7:
      return (input as TaskInput<7>).turns.length === 1 ? 3 : 0;
    case 6:
      return 5;
    default:
      return 1;
  }
}

/** 匿名帳號：app 產生的 UUID */
export const isAccount = (v: unknown): v is string => typeof v === 'string' && /^[A-Fa-f0-9-]{32,40}$/.test(v);

// ---------- StoreKit 2 的交易簽章（JWS，x5c 三張憑證） ----------

/** Apple Root CA - G3 的 SHA-256 指紋。沙盒實測前要再核對一次（Apple PKI 頁面） */
export const APPLE_ROOT_G3_SHA256 = '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179';
/** 葉憑證、中繼憑證上 Apple 放的標記 */
const LEAF_OID = '1.2.840.113635.100.6.11.1';
const INTER_OID = '1.2.840.113635.100.6.2.1';

export interface StoreKitOptions {
  bundleId: string;
  now: Date;
  /** 測試用：換掉 Apple 根憑證（給了就只信這一張） */
  rootPem?: string;
  /** 正式環境收不收沙盒的交易（TestFlight 是沙盒） */
  allowSandbox: boolean;
}

export interface Transaction {
  transactionId: string;
  productId: string;
  environment: string;
}

export class StoreKitError extends Error {}

const b64url = (s: string) => b64.decode(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4));

async function sha256Hex(b: Uint8Array): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', ab(b)));
  return [...d].map((x) => x.toString(16).padStart(2, '0')).join('');
}

/** 驗 app 送來的 Transaction.jwsRepresentation，回傳交易內容；不對就丟 StoreKitError */
export async function verifyTransaction(jws: string, opt: StoreKitOptions): Promise<Transaction> {
  const parts = jws.split('.');
  if (parts.length !== 3) throw new StoreKitError('不是 JWS');
  let header: any;
  let payload: any;
  try {
    header = JSON.parse(new TextDecoder().decode(b64url(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(b64url(parts[1])));
  } catch {
    throw new StoreKitError('JWS 讀不出來');
  }
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length !== 3) throw new StoreKitError('JWS 標頭不對');
  const ders = header.x5c.map((c: string) => b64.decode(c));
  const [leaf, inter, root] = ders.map(parseCertificate);

  // 根：測試給了就比對那張，正式比對 Apple Root CA - G3 的指紋
  if (opt.rootPem) {
    const want = pemToDer(opt.rootPem);
    if (want.length !== ders[2].length || !want.every((x, i) => x === ders[2][i])) throw new StoreKitError('根憑證不是 Apple 的');
  } else if ((await sha256Hex(ders[2])) !== APPLE_ROOT_G3_SHA256) {
    throw new StoreKitError('根憑證不是 Apple 的');
  }
  if (!leaf.extensions.has(LEAF_OID) || !inter.extensions.has(INTER_OID)) throw new StoreKitError('憑證少了 Apple 的標記');
  for (const c of [leaf, inter, root]) {
    if (opt.now < c.notBefore || opt.now > c.notAfter) throw new StoreKitError('憑證過期');
  }
  if (!(await verifySignedBy(leaf, inter)) || !(await verifySignedBy(inter, root))) throw new StoreKitError('憑證鏈對不上');

  // JWS 的簽章是 r‖s，直接給 WebCrypto
  const key = await crypto.subtle.importKey('spki', ab(leaf.spki), { name: 'ECDSA', namedCurve: leaf.curve }, false, ['verify']);
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, ab(b64url(parts[2])), ab(signed));
  if (!ok) throw new StoreKitError('簽章不對');

  if (payload.bundleId !== opt.bundleId) throw new StoreKitError('不是這個 app 的交易');
  if (payload.revocationDate) throw new StoreKitError('這筆已經退款');
  if (payload.environment !== 'Production' && !opt.allowSandbox) throw new StoreKitError('沙盒交易');
  if (typeof payload.transactionId !== 'string' || typeof payload.productId !== 'string') throw new StoreKitError('交易欄位不全');
  return { transactionId: payload.transactionId, productId: payload.productId, environment: String(payload.environment) };
}
