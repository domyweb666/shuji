-- wrangler d1 execute shuji-ai --remote --file=schema.sql
CREATE TABLE IF NOT EXISTS challenges (challenge TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS devices (key_id TEXT PRIMARY KEY, spki TEXT NOT NULL, counter INTEGER NOT NULL, env TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS quota (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL);
