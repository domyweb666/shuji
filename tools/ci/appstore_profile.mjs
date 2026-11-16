// 向 Apple 申請一張「上架用描述檔」（App Store provisioning profile），裝到這台機器上，
// 讓 exportArchive 用鑰匙圈裡那張 Apple Distribution 憑證手動簽章。
//
// 為什麼要這支：2026-11-15 踩到，exportArchive 走自動簽章時 Xcode 會去要「雲端簽章」，
// 那需要 Admin 等級的 API 金鑰，App Manager 等級會回 Cloud signing permission error。
// 改成自己申請描述檔，App Manager 金鑰就夠，也不用使用者到後台手動下載描述檔。
//
// 每次都把同名的舊描述檔刪掉重建：之後 App ID 多勾了能力（例如小工具），新的描述檔才會帶到。
// 一次只處理一個 bundle id；小工具 extension 那一張由 testflight.yml 換環境變數再跑一次。
//
// 用法（環境變數）：ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8_PATH、BUNDLE_ID、PROFILE_NAME、
// CERT_SERIAL（鑰匙圈裡那張發佈憑證的序號，十六進位）
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { ascClient, env } from "./asc_api.mjs";

const call = ascClient();
const bundleIdentifier = env("BUNDLE_ID");
const profileName = env("PROFILE_NAME");
const normalizeSerial = (serial) => serial.toUpperCase().replace(/^0+/, "");
const certSerial = normalizeSerial(env("CERT_SERIAL"));

const fail = (message) => {
  console.error(`::error::${message}`);
  process.exit(1);
};

try {
  const bundleIds = await call(
    "GET",
    `/v1/bundleIds?filter[identifier]=${encodeURIComponent(bundleIdentifier)}&limit=200`,
  );
  // filter[identifier] 是開頭比對，org.domyweb.shuji.widget 也會進來，所以再比一次全名
  const bundleId = bundleIds.data.find((item) => item.attributes.identifier === bundleIdentifier);
  if (!bundleId) {
    // 多半是登記時打錯一個字。把後台名字相近的 App ID 列出來（去掉最後一節再查一次），對一下就知道。
    const stem = bundleIdentifier.split(".").slice(0, -1).join(".");
    const near = await call(
      "GET",
      `/v1/bundleIds?filter[identifier]=${encodeURIComponent(stem)}&limit=200`,
    );
    const listed = near.data
      .map((item) => `${item.attributes.identifier}（${item.attributes.name}）`)
      .join("、");
    fail(
      `Apple 後台沒有 App ID ${bundleIdentifier}。請照 docs/TestFlight.md 第二步登記。` +
        `後台以 ${stem} 開頭的 App ID 有：${listed || "一個都沒有"}`,
    );
  }

  const certificates = await call(
    "GET",
    "/v1/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=200",
  );
  const certificate = certificates.data.find(
    (item) => normalizeSerial(item.attributes.serialNumber ?? "") === certSerial,
  );
  if (!certificate) {
    fail(
      `Apple 後台 ${certificates.data.length} 張發佈憑證裡，沒有一張跟鑰匙圈裡的 .p12 同序號。` +
        "這張 .p12 可能已被撤銷，或屬於另一個開發者帳號。",
    );
  }

  const existing = await call(
    "GET",
    `/v1/profiles?filter[name]=${encodeURIComponent(profileName)}&limit=200`,
  );
  for (const profile of existing.data.filter((item) => item.attributes.name === profileName)) {
    await call("DELETE", `/v1/profiles/${profile.id}`);
    console.log(`刪掉舊的描述檔 ${profileName}（${profile.attributes.uuid}）`);
  }

  const created = await call("POST", "/v1/profiles", {
    data: {
      type: "profiles",
      attributes: { name: profileName, profileType: "IOS_APP_STORE" },
      relationships: {
        bundleId: { data: { type: "bundleIds", id: bundleId.id } },
        certificates: { data: [{ type: "certificates", id: certificate.id }] },
      },
    },
  });
  const { uuid, profileContent, expirationDate } = created.data.attributes;

  // Xcode 16 起描述檔的家搬了；兩個位置都放，新舊版都找得到
  const folders = [
    join(homedir(), "Library/Developer/Xcode/UserData/Provisioning Profiles"),
    join(homedir(), "Library/MobileDevice/Provisioning Profiles"),
  ];
  for (const folder of folders) {
    mkdirSync(folder, { recursive: true });
    writeFileSync(join(folder, `${uuid}.mobileprovision`), Buffer.from(profileContent, "base64"));
  }
  console.log(`已建立並安裝描述檔 ${profileName}（${uuid}），到期日 ${expirationDate}`);
} catch (error) {
  if (error.status === 401 || error.status === 403) {
    fail(
      `App Store Connect 拒絕了這把 API 金鑰（${error.status}）。` +
        "金鑰的權限要是 App Manager 或 Admin，才能建立描述檔。" +
        `原始訊息：${error.message}`,
    );
  }
  fail(error.message);
}
