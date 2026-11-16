// App Store Connect API 的共用小工具：讀環境變數、簽 JWT、打 API。
// 只用 node 內建的 crypto 與 fetch，零套件。testflight_notes.mjs 與 appstore_profile.mjs 共用。
// 需要的環境變數：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8_PATH
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";

export const env = (name) => {
  const value = process.env[name];
  if (!value) {
    console.error(`缺環境變數 ${name}`);
    process.exit(2);
  }
  return value;
};

const API = "https://api.appstoreconnect.apple.com";
const base64url = (input) => Buffer.from(input).toString("base64url");

/// 回傳一個 call(method, path, body)。非 2xx 會丟錯，錯誤物件上帶 status。
export function ascClient() {
  const keyId = env("ASC_KEY_ID");
  const issuerId = env("ASC_ISSUER_ID");
  const privateKey = createPrivateKey(readFileSync(env("ASC_KEY_P8_PATH"), "utf8"));

  // JWT 有效 20 分鐘；每次呼叫重新簽，避免輪詢半小時後過期
  function token() {
    const now = Math.floor(Date.now() / 1000);
    const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
    const payload = base64url(
      JSON.stringify({ iss: issuerId, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" }),
    );
    const signature = sign("sha256", Buffer.from(`${header}.${payload}`), {
      key: privateKey,
      dsaEncoding: "ieee-p1363",
    });
    return `${header}.${payload}.${signature.toString("base64url")}`;
  }

  return async function call(method, path, body) {
    const response = await fetch(API + path, {
      method,
      headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await response.text();
    if (!response.ok) {
      const error = new Error(`${method} ${path} 回 ${response.status}：${text.slice(0, 500)}`);
      error.status = response.status;
      throw error;
    }
    return text ? JSON.parse(text) : null;
  };
}
