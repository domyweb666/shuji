import { createApp } from './app';
import type { AttestEnv } from './attest/appattest';
import { anthropicCaller } from './model';
import { D1Storage } from './storage';

// Cloudflare Workers 進入點。設定在 wrangler.toml，金鑰用 wrangler secret put。

export interface Env {
  DB: D1Database;
  ANTHROPIC_API_KEY: string;
  /** TEAMID.org.domyweb.shuji */
  APP_ID: string;
  /** 逗號分隔：production,development */
  ATTEST_ENVS: string;
  GLOBAL_DAILY_CAP: string;
  /** 選填，開發用（模擬器）。正式上架前刪掉：wrangler secret delete DEV_TOKEN */
  DEV_TOKEN?: string;
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (!env.APP_ID || env.APP_ID.startsWith('TEAMID')) {
      return new Response(JSON.stringify({ ok: false, error: 'unavailable', message: '伺服器還沒設定好。' }), { status: 503 });
    }
    const app = createApp({
      storage: new D1Storage(env.DB),
      caller: anthropicCaller(env.ANTHROPIC_API_KEY),
      config: {
        appId: env.APP_ID,
        allowEnvs: env.ATTEST_ENVS.split(',').map((s) => s.trim()).filter(Boolean) as AttestEnv[],
        devToken: env.DEV_TOKEN || undefined,
        globalDailyCap: Number(env.GLOBAL_DAILY_CAP) || 5000,
      },
    });
    try {
      return await app(req);
    } catch (e) {
      console.log(JSON.stringify({ ev: 'crash', reason: (e as Error).message }));
      return new Response(JSON.stringify({ ok: false, error: 'unavailable', message: '現在想不出來，你先自己填，等一下再試。' }), { status: 500 });
    }
  },
};
