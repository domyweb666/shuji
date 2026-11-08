import { asBytes, decodeCbor, mapGet } from './cbor';
import { OID, ab, parseCertificate, parseDer, pemToDer, importSpki, derSignatureToRaw, verifySignedBy } from './x509';

// Apple App Attest 伺服器端驗證，照 Apple 文件「Validating apps that connect to your server」的步驟。
// 註冊（attestation）一台裝置一次；之後每個請求帶 assertion，驗簽章與計數器。

/** https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
 *  SHA-256 指紋 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32 */
export const APPLE_APP_ATTEST_ROOT = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const AAGUID_DEV = new TextEncoder().encode('appattestdevelop');
const AAGUID_PROD = new Uint8Array([...new TextEncoder().encode('appattest'), 0, 0, 0, 0, 0, 0, 0]);

export type AttestEnv = 'development' | 'production';

export interface AttestOptions {
  /** TEAMID.bundleID，例如 ABCDE12345.org.domyweb.shuji */
  appId: string;
  /** 接受哪些環境。TestFlight／App Store 簽的是 production，Xcode 直接裝的是 development */
  allowEnvs: AttestEnv[];
  now?: Date;
  /** 測試用：換掉 Apple 根憑證 */
  rootPem?: string;
}

export interface RegisteredKey {
  keyId: string;
  /** 葉憑證的 SubjectPublicKeyInfo（base64），之後驗 assertion 用 */
  spki: string;
  counter: number;
  env: AttestEnv;
}

export class AttestError extends Error {}

export const b64 = {
  encode(b: Uint8Array): string {
    let s = '';
    for (const x of b) s += String.fromCharCode(x);
    return btoa(s);
  },
  decode(s: string): Uint8Array {
    return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  },
};

export async function sha256(...parts: Uint8Array[]): Promise<Uint8Array> {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const buf = new Uint8Array(total);
  let o = 0;
  for (const p of parts) {
    buf.set(p, o);
    o += p.length;
  }
  return new Uint8Array(await crypto.subtle.digest('SHA-256', buf));
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

interface AuthData {
  rpIdHash: Uint8Array;
  counter: number;
  aaguid?: Uint8Array;
  credentialId?: Uint8Array;
}

function parseAuthData(a: Uint8Array, withCredential: boolean): AuthData {
  if (a.length < 37) throw new AttestError('authenticatorData 太短');
  const rpIdHash = a.subarray(0, 32);
  const counter = new DataView(a.buffer, a.byteOffset + 33, 4).getUint32(0);
  if (!withCredential) return { rpIdHash, counter };
  if (a.length < 55) throw new AttestError('authenticatorData 沒有 credential');
  const aaguid = a.subarray(37, 53);
  const idLen = (a[53] << 8) | a[54];
  const credentialId = a.subarray(55, 55 + idLen);
  if (credentialId.length !== idLen) throw new AttestError('credentialId 長度不對');
  return { rpIdHash, counter, aaguid, credentialId };
}

/**
 * 驗一台裝置第一次送來的 attestation。
 * @param keyIdB64 app 用 DCAppAttestService.generateKey 拿到的 keyId（base64）
 * @param attestationB64 attestKey 回的 attestation object（base64）
 * @param challenge 伺服器剛發的挑戰字串，app 算 clientDataHash = SHA256(challenge 的 UTF-8)
 */
export async function verifyAttestation(keyIdB64: string, attestationB64: string, challenge: string, opt: AttestOptions): Promise<RegisteredKey> {
  const now = opt.now ?? new Date();
  let obj;
  try {
    obj = decodeCbor(b64.decode(attestationB64));
  } catch (e) {
    throw new AttestError(`attestation 讀不出來：${(e as Error).message}`);
  }
  if (mapGet(obj, 'fmt') !== 'apple-appattest') throw new AttestError('fmt 不是 apple-appattest');
  const attStmt = mapGet(obj, 'attStmt');
  const authData = asBytes(mapGet(obj, 'authData'), 'authData');
  const x5c = mapGet(attStmt!, 'x5c');
  if (!Array.isArray(x5c) || x5c.length < 2) throw new AttestError('x5c 不完整');

  // 1. 憑證鏈：葉 ← 中繼 ← Apple 根
  const leaf = parseCertificate(asBytes(x5c[0], 'x5c[0]'));
  const inter = parseCertificate(asBytes(x5c[1], 'x5c[1]'));
  const root = parseCertificate(pemToDer(opt.rootPem ?? APPLE_APP_ATTEST_ROOT));
  for (const c of [leaf, inter, root]) {
    if (now < c.notBefore || now > c.notAfter) throw new AttestError('憑證不在有效期內');
  }
  if (!(await verifySignedBy(inter, root))) throw new AttestError('中繼憑證不是 Apple 根簽的');
  if (!(await verifySignedBy(leaf, inter))) throw new AttestError('葉憑證不是中繼簽的');

  // 2–4. nonce = SHA256(authData ‖ SHA256(challenge))，要等於葉憑證擴充欄位裡的那個
  const clientDataHash = await sha256(new TextEncoder().encode(challenge));
  const nonce = await sha256(authData, clientDataHash);
  const ext = leaf.extensions.get(OID.appAttestNonce);
  if (!ext) throw new AttestError('葉憑證沒有 nonce 擴充欄位');
  // SEQUENCE { [1] EXPLICIT OCTET STRING }
  const seq = parseDer(ext);
  const tagged = seq.children.find((t) => t.tag === 0xa1);
  const octet = tagged?.children[0];
  if (!octet || octet.tag !== 0x04 || !equal(octet.value, nonce)) throw new AttestError('nonce 對不上');

  // 5. keyId = SHA256(葉憑證公鑰)
  const keyId = b64.decode(keyIdB64);
  if (!equal(await sha256(leaf.publicPoint), keyId)) throw new AttestError('keyId 跟公鑰對不上');

  // 6–9. authData：App ID、計數器 0、環境、credentialId
  const ad = parseAuthData(authData, true);
  if (!equal(ad.rpIdHash, await sha256(new TextEncoder().encode(opt.appId)))) throw new AttestError('App ID 對不上');
  if (ad.counter !== 0) throw new AttestError('註冊時計數器不是 0');
  const env: AttestEnv | null = equal(ad.aaguid!, AAGUID_PROD) ? 'production' : equal(ad.aaguid!, AAGUID_DEV) ? 'development' : null;
  if (!env || !opt.allowEnvs.includes(env)) throw new AttestError(`環境不接受：${env ?? '未知'}`);
  if (!equal(ad.credentialId!, keyId)) throw new AttestError('credentialId 跟 keyId 對不上');

  return { keyId: keyIdB64, spki: b64.encode(leaf.spki), counter: 0, env };
}

/**
 * 驗每個請求的 assertion。clientData 是 app 簽的那段原始位元組（就是請求 body）。
 * 回傳新的計數器，呼叫端要存回去；計數器沒有往上加代表是重放。
 */
export async function verifyAssertion(key: RegisteredKey, assertionB64: string, clientData: Uint8Array, appId: string): Promise<number> {
  let obj;
  try {
    obj = decodeCbor(b64.decode(assertionB64));
  } catch (e) {
    throw new AttestError(`assertion 讀不出來：${(e as Error).message}`);
  }
  const signature = asBytes(mapGet(obj, 'signature'), 'signature');
  const authData = asBytes(mapGet(obj, 'authenticatorData'), 'authenticatorData');

  const nonce = await sha256(authData, await sha256(clientData));
  const pub = await importSpki(b64.decode(key.spki), 'P-256');
  const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pub, ab(derSignatureToRaw(signature, 32)), ab(nonce));
  if (!ok) throw new AttestError('assertion 簽章不對');

  const ad = parseAuthData(authData, false);
  if (!equal(ad.rpIdHash, await sha256(new TextEncoder().encode(appId)))) throw new AttestError('App ID 對不上');
  if (ad.counter <= key.counter) throw new AttestError('計數器沒有往上加（重放？）');
  return ad.counter;
}
