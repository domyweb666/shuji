import type { RegisteredKey } from './attest/appattest';

// 三種東西要存：註冊挑戰（一次性、五分鐘）、裝置公鑰與計數器、次數。
// 正式環境用 D1（SQLite），測試用記憶體版。使用者寫的內容一個字都不存。

export interface Storage {
  putChallenge(challenge: string, expiresAt: number): Promise<void>;
  /** 用掉一個挑戰：存在且沒過期就刪掉並回 true */
  takeChallenge(challenge: string, now: number): Promise<boolean>;
  getKey(keyId: string): Promise<RegisteredKey | null>;
  putKey(key: RegisteredKey, now: number): Promise<void>;
  /** 只在新計數器比舊的大時才更新，回傳有沒有更新（擋同時送來的重放） */
  bumpCounter(keyId: string, counter: number): Promise<boolean>;
  /** 次數加一，回傳加完之後的值 */
  incr(bucket: string, expiresAt: number, now: number): Promise<number>;
  /** 把剛加上去的一次退回去（模型出錯、沒產出東西時，不算使用者的次數） */
  decr(bucket: string): Promise<void>;
}

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS challenges (challenge TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS devices (key_id TEXT PRIMARY KEY, spki TEXT NOT NULL, counter INTEGER NOT NULL, env TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS quota (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL);
`;

export class D1Storage implements Storage {
  constructor(private db: D1Database) {}

  async putChallenge(challenge: string, expiresAt: number) {
    await this.db.prepare('INSERT INTO challenges (challenge, expires_at) VALUES (?, ?)').bind(challenge, expiresAt).run();
  }

  async takeChallenge(challenge: string, now: number) {
    const r = await this.db.prepare('DELETE FROM challenges WHERE challenge = ? AND expires_at > ?').bind(challenge, now).run();
    // 順手清掉過期的
    await this.db.prepare('DELETE FROM challenges WHERE expires_at <= ?').bind(now).run();
    return (r.meta.changes ?? 0) > 0;
  }

  async getKey(keyId: string) {
    const r = await this.db.prepare('SELECT key_id, spki, counter, env FROM devices WHERE key_id = ?').bind(keyId).first<{ key_id: string; spki: string; counter: number; env: string }>();
    return r ? { keyId: r.key_id, spki: r.spki, counter: r.counter, env: r.env as RegisteredKey['env'] } : null;
  }

  async putKey(key: RegisteredKey, now: number) {
    await this.db
      .prepare('INSERT OR REPLACE INTO devices (key_id, spki, counter, env, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(key.keyId, key.spki, key.counter, key.env, now)
      .run();
  }

  async bumpCounter(keyId: string, counter: number) {
    const r = await this.db.prepare('UPDATE devices SET counter = ? WHERE key_id = ? AND counter < ?').bind(counter, keyId, counter).run();
    return (r.meta.changes ?? 0) > 0;
  }

  async incr(bucket: string, expiresAt: number, now: number) {
    const r = await this.db
      .prepare(
        `INSERT INTO quota (bucket, count, expires_at) VALUES (?1, 1, ?2)
         ON CONFLICT(bucket) DO UPDATE SET
           count = CASE WHEN quota.expires_at <= ?3 THEN 1 ELSE quota.count + 1 END,
           expires_at = CASE WHEN quota.expires_at <= ?3 THEN ?2 ELSE quota.expires_at END
         RETURNING count`,
      )
      .bind(bucket, expiresAt, now)
      .first<{ count: number }>();
    return r?.count ?? 1;
  }

  async decr(bucket: string) {
    await this.db.prepare('UPDATE quota SET count = count - 1 WHERE bucket = ? AND count > 0').bind(bucket).run();
  }
}

export class MemoryStorage implements Storage {
  challenges = new Map<string, number>();
  keys = new Map<string, RegisteredKey>();
  quota = new Map<string, { count: number; expiresAt: number }>();

  async putChallenge(c: string, e: number) {
    this.challenges.set(c, e);
  }
  async takeChallenge(c: string, now: number) {
    const e = this.challenges.get(c);
    this.challenges.delete(c);
    return e !== undefined && e > now;
  }
  async getKey(id: string) {
    const k = this.keys.get(id);
    return k ? { ...k } : null;
  }
  async putKey(k: RegisteredKey) {
    this.keys.set(k.keyId, { ...k });
  }
  async bumpCounter(id: string, counter: number) {
    const k = this.keys.get(id);
    if (!k || counter <= k.counter) return false;
    k.counter = counter;
    return true;
  }
  async incr(b: string, e: number, now: number) {
    const q = this.quota.get(b);
    if (!q || q.expiresAt <= now) {
      this.quota.set(b, { count: 1, expiresAt: e });
      return 1;
    }
    q.count += 1;
    return q.count;
  }
  async decr(b: string) {
    const q = this.quota.get(b);
    if (q && q.count > 0) q.count -= 1;
  }
}
