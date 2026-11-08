// App Attest 只用到 CBOR 的一小部分：map、array、byte string、text string、整數。
// 不支援的型別直接丟錯，讓驗證失敗，不猜。

export type CborValue = number | bigint | string | Uint8Array | CborValue[] | Map<CborValue, CborValue> | boolean | null;

export function decodeCbor(bytes: Uint8Array): CborValue {
  const r = new Reader(bytes);
  const v = r.item(0);
  if (r.pos !== bytes.length) throw new Error('CBOR 後面還有多餘的位元組');
  return v;
}

class Reader {
  pos = 0;
  constructor(private b: Uint8Array) {}

  private byte(): number {
    if (this.pos >= this.b.length) throw new Error('CBOR 讀到結尾');
    return this.b[this.pos++];
  }

  private take(n: number): Uint8Array {
    if (this.pos + n > this.b.length) throw new Error('CBOR 長度超出');
    const out = this.b.subarray(this.pos, this.pos + n);
    this.pos += n;
    return out;
  }

  private arg(info: number): number {
    if (info < 24) return info;
    if (info === 24) return this.byte();
    if (info === 25) return (this.byte() << 8) | this.byte();
    if (info === 26) {
      const v = new DataView(this.b.buffer, this.b.byteOffset + this.pos, 4).getUint32(0);
      this.pos += 4;
      return v;
    }
    if (info === 27) {
      const v = new DataView(this.b.buffer, this.b.byteOffset + this.pos, 8).getBigUint64(0);
      this.pos += 8;
      if (v > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('CBOR 整數太大');
      return Number(v);
    }
    throw new Error(`CBOR 不支援長度編碼 ${info}`);
  }

  item(depth: number): CborValue {
    if (depth > 16) throw new Error('CBOR 巢狀太深');
    const head = this.byte();
    const major = head >> 5;
    const info = head & 0x1f;
    switch (major) {
      case 0:
        return this.arg(info);
      case 1:
        return -1 - this.arg(info);
      case 2:
        return this.take(this.arg(info)).slice();
      case 3:
        return new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(this.take(this.arg(info)));
      case 4: {
        const n = this.arg(info);
        if (n > 64) throw new Error('CBOR 陣列太長');
        const arr: CborValue[] = [];
        for (let i = 0; i < n; i++) arr.push(this.item(depth + 1));
        return arr;
      }
      case 5: {
        const n = this.arg(info);
        if (n > 64) throw new Error('CBOR map 太大');
        const m = new Map<CborValue, CborValue>();
        for (let i = 0; i < n; i++) {
          const k = this.item(depth + 1);
          m.set(k, this.item(depth + 1));
        }
        return m;
      }
      case 7:
        if (info === 20) return false;
        if (info === 21) return true;
        if (info === 22) return null;
        throw new Error(`CBOR 不支援 simple ${info}`);
      default:
        throw new Error(`CBOR 不支援 major type ${major}`);
    }
  }
}

export function mapGet(m: CborValue, key: string): CborValue | undefined {
  if (!(m instanceof Map)) throw new Error('CBOR 不是 map');
  return m.get(key);
}

export function asBytes(v: CborValue | undefined, what: string): Uint8Array {
  if (!(v instanceof Uint8Array)) throw new Error(`${what} 不是 byte string`);
  return v;
}
