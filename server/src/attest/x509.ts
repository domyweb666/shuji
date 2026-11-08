// 驗 App Attest 憑證鏈需要的最小 X.509／DER 解析。只讀不寫。
// 公鑰直接把整段 SubjectPublicKeyInfo 交給 WebCrypto 匯入，不自己解點座標。

export interface Tlv {
  tag: number;
  /** 整個 TLV（含標頭）的位元組，算簽章時用 */
  raw: Uint8Array;
  /** 內容 */
  value: Uint8Array;
  /** 只在 constructed 時解開 */
  children: Tlv[];
}

function readTlv(b: Uint8Array, pos: number, depth: number): { tlv: Tlv; next: number } {
  if (depth > 20) throw new Error('DER 巢狀太深');
  const start = pos;
  const tag = b[pos++];
  if (tag === undefined) throw new Error('DER 讀到結尾');
  let len = b[pos++];
  if (len === undefined) throw new Error('DER 讀到結尾');
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4) throw new Error('DER 長度編碼不支援');
    len = 0;
    for (let i = 0; i < n; i++) len = (len << 8) | b[pos++];
  }
  const end = pos + len;
  if (end > b.length) throw new Error('DER 長度超出');
  const value = b.subarray(pos, end);
  const constructed = (tag & 0x20) !== 0;
  const children: Tlv[] = [];
  if (constructed) {
    let p = 0;
    while (p < value.length) {
      const r = readTlv(value, p, depth + 1);
      children.push(r.tlv);
      p = r.next;
    }
  }
  return { tlv: { tag, raw: b.subarray(start, end), value, children }, next: end };
}

export function parseDer(b: Uint8Array): Tlv {
  const r = readTlv(b, 0, 0);
  if (r.next !== b.length) throw new Error('DER 後面還有多餘的位元組');
  return r.tlv;
}

export function oidToString(v: Uint8Array): string {
  const parts: number[] = [Math.floor(v[0] / 40), v[0] % 40];
  let n = 0;
  for (let i = 1; i < v.length; i++) {
    n = n * 128 + (v[i] & 0x7f);
    if (!(v[i] & 0x80)) {
      parts.push(n);
      n = 0;
    }
  }
  return parts.join('.');
}

export const OID = {
  ecdsaSha256: '1.2.840.10045.4.3.2',
  ecdsaSha384: '1.2.840.10045.4.3.3',
  ecPublicKey: '1.2.840.10045.2.1',
  p256: '1.2.840.10045.3.1.7',
  p384: '1.3.132.0.34',
  appAttestNonce: '1.2.840.113635.100.8.2',
};

export interface Certificate {
  tbs: Uint8Array;
  sigAlg: string;
  signature: Uint8Array;
  spki: Uint8Array;
  curve: 'P-256' | 'P-384';
  /** SPKI 裡的公鑰點（04 開頭的未壓縮格式） */
  publicPoint: Uint8Array;
  notBefore: Date;
  notAfter: Date;
  extensions: Map<string, Uint8Array>;
}

function parseTime(t: Tlv): Date {
  const s = new TextDecoder().decode(t.value);
  // UTCTime YYMMDDHHMMSSZ／GeneralizedTime YYYYMMDDHHMMSSZ
  const m = t.tag === 0x17 ? s.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/) : s.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/);
  if (!m) throw new Error(`憑證時間格式不支援：${s}`);
  let year = Number(m[1]);
  if (t.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return new Date(Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])));
}

export function parseCertificate(der: Uint8Array): Certificate {
  const cert = parseDer(der);
  const [tbsT, algT, sigT] = cert.children;
  if (!tbsT || !algT || !sigT || sigT.tag !== 0x03) throw new Error('不是 X.509 憑證');
  const tbsKids = tbsT.children;
  // [0] version 可能有可能沒有
  const off = tbsKids[0]?.tag === 0xa0 ? 1 : 0;
  const validity = tbsKids[off + 3];
  const spkiT = tbsKids[off + 5];
  if (!validity || !spkiT) throw new Error('憑證欄位不全');

  const [keyAlg, keyBits] = spkiT.children;
  const keyAlgOid = oidToString(keyAlg.children[0].value);
  const curveOid = keyAlg.children[1] ? oidToString(keyAlg.children[1].value) : '';
  if (keyAlgOid !== OID.ecPublicKey) throw new Error('憑證公鑰不是 EC');
  const curve = curveOid === OID.p256 ? 'P-256' : curveOid === OID.p384 ? 'P-384' : null;
  if (!curve) throw new Error(`不支援的曲線 ${curveOid}`);

  const extensions = new Map<string, Uint8Array>();
  const extWrap = tbsKids.find((t) => t.tag === 0xa3);
  if (extWrap) {
    for (const ext of extWrap.children[0].children) {
      const id = oidToString(ext.children[0].value);
      const valueT = ext.children[ext.children.length - 1];
      extensions.set(id, valueT.value);
    }
  }

  return {
    tbs: tbsT.raw,
    sigAlg: oidToString(algT.children[0].value),
    signature: sigT.value.subarray(1), // 去掉 unused-bits 那一個位元組
    spki: spkiT.raw,
    curve,
    publicPoint: keyBits.value.subarray(1),
    notBefore: parseTime(validity.children[0]),
    notAfter: parseTime(validity.children[1]),
    extensions,
  };
}

export function pemToDer(pem: string): Uint8Array {
  const b64 = pem.replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** ECDSA 的 DER 簽章（SEQUENCE { r, s }）轉成 WebCrypto 要的 r‖s */
export function derSignatureToRaw(sig: Uint8Array, size: number): Uint8Array {
  const seq = parseDer(sig);
  if (seq.children.length !== 2) throw new Error('簽章格式錯');
  const out = new Uint8Array(size * 2);
  seq.children.forEach((intT, i) => {
    let v = intT.value;
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) throw new Error('簽章整數太長');
    out.set(v, i * size + (size - v.length));
  });
  return out;
}

/** WebCrypto 要的是 ArrayBuffer 底的 view；複製一份就確定是 */
export const ab = (u: Uint8Array): Uint8Array<ArrayBuffer> => new Uint8Array(u);

export async function importSpki(spki: Uint8Array, curve: 'P-256' | 'P-384'): Promise<CryptoKey> {
  return crypto.subtle.importKey('spki', ab(spki), { name: 'ECDSA', namedCurve: curve }, false, ['verify']);
}

/** 用 issuer 的公鑰驗 subject 這張憑證的簽章 */
export async function verifySignedBy(subject: Certificate, issuer: Certificate): Promise<boolean> {
  const hash = subject.sigAlg === OID.ecdsaSha256 ? 'SHA-256' : subject.sigAlg === OID.ecdsaSha384 ? 'SHA-384' : null;
  if (!hash) throw new Error(`不支援的簽章演算法 ${subject.sigAlg}`);
  const key = await importSpki(issuer.spki, issuer.curve);
  const size = issuer.curve === 'P-256' ? 32 : 48;
  return crypto.subtle.verify({ name: 'ECDSA', hash }, key, ab(derSignatureToRaw(subject.signature, size)), ab(subject.tbs));
}
