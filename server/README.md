# 薯記 AI 中繼伺服器

app 不直接打 Claude。金鑰放在 app 裡一定會被拆出來，所以中間隔一台小伺服器：它保管金鑰、確認請求真的來自薯記（App Attest）、擋次數、組提示、檢查輸出，再把結果回給 app。使用者寫的字它不存。

跑在 Cloudflare Workers，資料庫是 D1，免費額度撐得住幾千個使用者。

## 它做的事

| 步驟 | 做什麼 |
|---|---|
| 認裝置 | 第一次用時 app 做 App Attest 註冊；之後每個請求都帶簽章，伺服器驗簽章和計數器 |
| 擋次數 | 照 `ai/提示詞與輸出格式.md`：種下去助手一天 10 次、三問診斷一週 2 次⋯⋯；全站一天上限 5000 次 |
| 組提示 | 護欄包＋任務的知識包＋任務指令，前兩段快取 |
| 問模型 | 任務 1–5 用 Haiku 5.5，任務 6 用 Sonnet 5.5，強制回 JSON |
| 檢查 | 禁用詞、否定句、固定結語、週回顧不出數字；不過就重問一次，再不過叫 app 回手動流程 |

知識包和任務指令從 repo 根目錄的 `ai/` 打包進來。改書的內容就改 `ai/`，重新部署。

## 第一次部署

要一個 Cloudflare 帳號（免費）和一把 Anthropic API 金鑰。在 `server/` 資料夾裡：

1. 登入 Cloudflare，會開瀏覽器：

   ```bash
   npx wrangler login
   ```

2. 建資料庫，把印出來的 `database_id` 貼進 `wrangler.toml`：

   ```bash
   npx wrangler d1 create shuji-ai
   ```

3. 建資料表：

   ```bash
   npx wrangler d1 execute shuji-ai --remote --file=schema.sql
   ```

4. 打開 `wrangler.toml`，把 `APP_ID` 的 `TEAMID` 換成你的 Team ID（developer.apple.com 帳號頁的 Membership details）。

5. 放 Anthropic 金鑰（會問你貼上）：

   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY
   ```

6. 部署：

   ```bash
   npm run deploy
   ```

   最後一行會印出網址，長得像 `https://shuji-ai.你的名字.workers.dev`。

7. 把網址填進 `Shuji/Info.plist` 的 `ShujiAIBaseURL`，app 的 AI 按鈕才會出現。

8. 到 Anthropic Console 的 Limits 設一個每月花費上限，萬一出事有天花板。

## 模擬器怎麼測

模擬器沒有 App Attest。給伺服器一組開發用通行碼：

```bash
npx wrangler secret put DEV_TOKEN
```

在 Debug 版 app 的設定頁最下面「測試區」貼同一組通行碼。正式上架前刪掉：

```bash
npx wrangler secret delete DEV_TOKEN
```

## 測試

```bash
npm test
```

不花錢，不連網路。App Attest 用測試裡自己造的假 Apple 憑證鏈驗。

真的打模型、跑 `ai/提示詞與輸出格式.md` 最後那張測試清單（會花錢，一輪大約一百次呼叫）：

```bash
npm run eval
```

金鑰讀環境變數 `ANTHROPIC_API_KEY`，或 repo 外面的 `E:\習慣地瓜\簽章\anthropic-api-key.txt`。報告寫在 `eval/out/latest.md`。

## 回應格式

成功：`{ ok: true, task, result, referral? }`。`result` 是任務的 JSON；`type` 是 `unfit` 時多帶 `referral`，是護欄包第六節的固定轉介文字。

失敗：`{ ok: false, error, message }`。`message` 直接給使用者看。

| HTTP | error | 什麼時候 |
|---|---|---|
| 400 | bad_request | 格式錯、手機時間差超過五分鐘 |
| 401 | attest_failed／not_registered | 裝置驗證不過、還沒註冊 |
| 429 | rate_limited | 次數用完 |
| 502 | bad_output | 模型兩次都沒給出合規的輸出 |
| 503 | unavailable | 全站上限到了、伺服器沒設定好 |
