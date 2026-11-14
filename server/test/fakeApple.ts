// 測試用：照 Apple App Attest 的格式，自己造一條「根 → 中繼 → 裝置葉憑證」的憑證鏈，
// 產生 attestation 與 assertion。驗證程式拿這個根當信任起點，就能在沒有 iPhone 的地方測。
import { createHash, generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import { Encoder } from 'cbor-x';

// ---------- 最小 DER 編碼 ----------

function len(n: number): number[] {
  if (n < 0x80) return [n];
  const out: number[] = [];
  while (n > 0) {
    out.unshift(n & 0xff);
    n >>= 8;
  }
  return [0x80 | out.length, ...out];
}
const tlv = (tag: number, body: Uint8Array) => Uint8Array.from([tag, ...len(body.length), ...body]);
const cat = (...parts: Uint8Array[]) => Uint8Array.from(parts.flatMap((p) => [...p]));
const seq = (...p: Uint8Array[]) => tlv(0x30, cat(...p));
const set = (...p: Uint8Array[]) => tlv(0x31, cat(...p));
const int = (n: number) => tlv(0x02, Uint8Array.from([n]));
const octet = (b: Uint8Array) => tlv(0x04, b);
const bitstring = (b: Uint8Array) => tlv(0x03, cat(Uint8Array.from([0]), b));
const utf8 = (s: string) => tlv(0x0c, new TextEncoder().encode(s));
const explicit = (n: number, inner: Uint8Array) => tlv(0xa0 | n, inner);
function oid(s: string): Uint8Array {
  const p = s.split('.').map(Number);
  const out = [p[0] * 40 + p[1]];
  for (const v of p.slice(2)) {
    const bytes = [v & 0x7f];
    let x = v >> 7;
    while (x > 0) {
      bytes.unshift((x & 0x7f) | 0x80);
      x >>= 7;
    }
    out.push(...bytes);
  }
  return tlv(0x06, Uint8Array.from(out));
}
// 假憑證從十年前開始有效：測試會把「現在」釘在固定日期（app.test.ts 的 NOW），
// 開始日期跟著真實時鐘走的話，過了那天測試就會說憑證還沒生效。
const VALID_BACK = 3650 * 86400e3;

function utctime(d: Date): Uint8Array {
  const p = (n: number) => String(n).padStart(2, '0');
  const s = `${p(d.getUTCFullYear() % 100)}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`;
  return tlv(0x17, new TextEncoder().encode(s));
}
const name = (cn: string) => seq(set(seq(oid('2.5.4.3'), utf8(cn))));

const SHA256 = '1.2.840.10045.4.3.2';
const SHA384 = '1.2.840.10045.4.3.3';

interface Issued {
  der: Uint8Array;
  key: KeyObject;
  pub: KeyObject;
  cn: string;
}

function issue(opts: {
  cn: string;
  curve: 'P-256' | 'P-384';
  issuer?: Issued;
  hash: 'sha256' | 'sha384';
  extensions?: Uint8Array[];
  notBefore?: Date;
  notAfter?: Date;
}): Issued {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: opts.curve === 'P-256' ? 'prime256v1' : 'secp384r1' });
  const spki = new Uint8Array(publicKey.export({ type: 'spki', format: 'der' }));
  const alg = seq(oid(opts.hash === 'sha256' ? SHA256 : SHA384));
  const parts = [
    explicit(0, int(2)),
    int(Math.floor(Math.random() * 100) + 1),
    alg,
    name(opts.issuer?.cn ?? opts.cn),
    seq(utctime(opts.notBefore ?? new Date(Date.now() - VALID_BACK)), utctime(opts.notAfter ?? new Date(Date.now() + 365 * 86400e3))),
    name(opts.cn),
    spki,
  ];
  if (opts.extensions?.length) parts.push(explicit(3, seq(...opts.extensions)));
  const tbs = seq(...parts);
  const signer = opts.issuer?.key ?? privateKey;
  const sig = new Uint8Array(sign(opts.hash, tbs, signer));
  return { der: seq(tbs, alg, bitstring(sig)), key: privateKey, pub: publicKey, cn: opts.cn };
}

function pem(der: Uint8Array): string {
  const b64 = Buffer.from(der).toString('base64').match(/.{1,64}/g)!.join('\n');
  return `-----BEGIN CERTIFICATE-----\n${b64}\n-----END CERTIFICATE-----`;
}

const h = (...parts: Uint8Array[]) => new Uint8Array(createHash('sha256').update(Buffer.concat(parts.map((p) => Buffer.from(p)))).digest());

const cbor = new Encoder({ useRecords: false, mapsAsObjects: true, tagUint8Array: false });
const enc = (v: unknown) => new Uint8Array(cbor.encode(v));
const buf = (u: Uint8Array) => Buffer.from(u);

export const AAGUID_DEV = new TextEncoder().encode('appattestdevelop');
export const AAGUID_PROD = Uint8Array.from([...new TextEncoder().encode('appattest'), 0, 0, 0, 0, 0, 0, 0]);

export class FakeApple {
  root = issue({ cn: 'Fake App Attestation Root CA', curve: 'P-384', hash: 'sha384' });
  inter = issue({ cn: 'Fake App Attestation CA 1', curve: 'P-384', hash: 'sha384', issuer: this.root });
  get rootPem() {
    return pem(this.root.der);
  }

  /** 一台假 iPhone：產生 key 與 attestation，之後每個請求簽 assertion */
  device(appId: string, opts: { aaguid?: Uint8Array; counter?: number; interOverride?: Issued } = {}) {
    const apple = this;
    const leafKeys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const spki = new Uint8Array(leafKeys.publicKey.export({ type: 'spki', format: 'der' }));
    const point = spki.subarray(spki.length - 65);
    const keyId = h(point);
    const keyIdB64 = Buffer.from(keyId).toString('base64');
    let counter = 0;

    return {
      keyId: keyIdB64,
      attest(challenge: string, override: { appId?: string; nonce?: Uint8Array } = {}) {
        const authData = cat(
          h(new TextEncoder().encode(override.appId ?? appId)),
          Uint8Array.from([0x41]),
          Uint8Array.from([0, 0, 0, opts.counter ?? 0]),
          opts.aaguid ?? AAGUID_DEV,
          Uint8Array.from([0, keyId.length]),
          keyId,
          Uint8Array.from([0xa5, 0x01, 0x02]), // COSE 公鑰，驗證不讀它
        );
        const nonce = override.nonce ?? h(authData, h(new TextEncoder().encode(challenge)));
        const ext = seq(oid('1.2.840.113635.100.8.2'), octet(seq(explicit(1, octet(nonce)))));
        const issuer = opts.interOverride ?? apple.inter;
        // 葉憑證要用跟裝置同一把公鑰：重新簽一張帶這把公鑰的
        const tbsParts = [
          explicit(0, int(2)),
          int(7),
          seq(oid(SHA256)),
          name(issuer.cn),
          seq(utctime(new Date(Date.now() - VALID_BACK)), utctime(new Date(Date.now() + 30 * 86400e3))),
          name('fake leaf'),
          spki,
          explicit(3, seq(ext)),
        ];
        const tbs = seq(...tbsParts);
        const sig = new Uint8Array(sign('sha256', tbs, issuer.key));
        const leafDer = seq(tbs, seq(oid(SHA256)), bitstring(sig));
        const obj = { fmt: 'apple-appattest', attStmt: { x5c: [buf(leafDer), buf(issuer.der)], receipt: buf(new Uint8Array([1, 2, 3])) }, authData: buf(authData) };
        return Buffer.from(enc(obj)).toString('base64');
      },
      assert(clientData: Uint8Array, override: { appId?: string; counter?: number } = {}) {
        counter = override.counter ?? counter + 1;
        const authData = cat(
          h(new TextEncoder().encode(override.appId ?? appId)),
          Uint8Array.from([0x01]),
          Uint8Array.from([(counter >> 24) & 0xff, (counter >> 16) & 0xff, (counter >> 8) & 0xff, counter & 0xff]),
        );
        const nonce = h(authData, h(clientData));
        const signature = new Uint8Array(sign('sha256', nonce, leafKeys.privateKey));
        return Buffer.from(enc({ signature: buf(signature), authenticatorData: buf(authData) })).toString('base64');
      },
    };
  }
}

/** 另一個不相干的根簽出來的中繼，用來測「不是 Apple 簽的」 */
export function strangerIntermediate(): Issued {
  const root = issue({ cn: 'Stranger Root', curve: 'P-384', hash: 'sha384' });
  return issue({ cn: 'Fake App Attestation CA 1', curve: 'P-384', hash: 'sha384', issuer: root });
}
