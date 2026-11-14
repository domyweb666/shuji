# Handoff: AI 六個任務、App Attest、一次買斷都寫完，PR #6 草稿 CI 綠；卡在金鑰與部署

> 產出時間：2026-11-08 15:00
> repo：`E:\習慣地瓜\shuji`（github.com/domyweb666/shuji，gh 已登入 domyweb666）
> 分支：`ai-v2`（PR #6，草稿，未合併）；`testflight` 分支另有 TestFlight 上傳流程，也還沒合併

## ✅ 這次完成了什麼

- 使用者把早上跟 Claude 聊完的 `ai/`（交接、五份知識包、提示詞與輸出格式）和 `docs/習慣-app-0*.md` 推上 main（1305b4c）。
- 使用者拍板：六個任務全做含付費；這次就做 App Attest；給金鑰讓我真打模型跑測試清單。
- `server/`：Cloudflare Workers + D1。`@anthropic-ai/sdk` 1.6 + zod v4 結構化輸出。任務 1–5 Haiku 5.5 effort low，任務 6 Sonnet 5.5 effort medium + server-side fallback。`scripts/gen-packs.mjs` 把 `ai/` 打包進 `src/generated/packs.ts`（gitignore）。App Attest 自寫 CBOR／X.509，釘 Apple 根憑證（SHA-256 1C:B9:82:3B…）。次數照提示詞文件，台灣時間。輸出檢查 `src/checks.ts`。59 個 vitest，用 `test/fakeApple.ts` 自造憑證鏈。`eval/run.ts` 是真打模型的測試清單。
- App：`Shuji/AI/` 五個檔。入口在首次設定、今天頁、設定頁、讓開始更容易、田。第一次送出前取得同意。StoreKit 2 一次買斷 `org.domyweb.shuji.full` 解鎖週回顧、季稽核、小工具。PrivacyInfo 申報使用者內容與 UserDefaults。`Info.plist` 的 `ShujiAIBaseURL` 是空的，所以 AI 按鈕目前都不出現。
- CI 多一個 Node 工作（typecheck、test、wrangler dry-run）。PR #6 第二次 run 42455494595 全綠：Swift 52 測試、零警告。

## 🚧 卡在使用者

1. **Anthropic 金鑰**：請使用者放到 `E:\習慣地瓜\簽章\anthropic-api-key.txt`。放了就在 `server/` 跑 `npm run eval`，看 `eval/out/latest.md`，不過的調 `src/checks.ts` 或回報 `ai/` 的提示詞問題。
2. **Cloudflare 帳號**：照 `server/README.md` 部署（wrangler login 要使用者自己開瀏覽器）。部署後把網址填進 `Shuji/Info.plist` 的 `ShujiAIBaseURL`。`wrangler.toml` 的 `APP_ID` 要換 Team ID、`database_id` 要貼 d1 create 的結果。
3. **App Store Connect**：建非消耗型內購 `org.domyweb.shuji.full`（價格使用者定，交接檔舉例 NT$150）；申請小型企業計畫（15%）。
4. **TestFlight**：`testflight` 分支等使用者交 distribution.cer、AuthKey .p8、Key ID、Issuer ID、Team ID（步驟在該分支的 `docs/TestFlight.md`）。

## 📌 關鍵決策（別再爭論）

- 交接檔寫 temperature 0.3，沒送：API 2026-10-21 起 temperature 一律 400，Haiku 5.5 也不收非預設值。用 effort。
- 輸出欄位「有時候沒有」一律 null 不省略（結構化輸出要求）。app 的 Decodable 用 Optional。
- 伺服器覆寫三樣：任務 1 的 example 用 floors[0]、triggers[0] 重組；任務 4 的 closing 換固定句、layer 0 換固定建議；任務 6 的 warn 不在三句內就清空。
- 週回顧 summary 只擋阿拉伯數字和 %，中文數字放行：診斷知識包明文允許「週末那兩天開關好像沒出現」。
- App Attest 沒加 entitlement，伺服器兩種環境都收（`ATTEST_ENVS`）。模擬器走 Debug 測試區的開發通行碼，伺服器 `DEV_TOKEN` secret，上架前刪。
- 「收集物樣式」沒做：機制表沒定義，且明文不做稀有收集物。
- 障礙版與備用開關在原生版是同一格「不順的時候」，伺服器回 `obstacle` 也寫進 backup。

## 📂 重要檔案

- `ai/` ← 唯一來源；改書就改這裡再部署
- `server/README.md`、`server/src/app.ts`（路由與次數）、`server/src/checks.ts`（輸出檢查）、`server/src/attest/appattest.ts`、`server/eval/run.ts`
- `Shuji/AI/AIClient.swift`（App Attest 與請求）、`AIViews.swift`（所有畫面）、`AIInputs.swift`（從紀錄組輸入）、`Purchases.swift`
- `docs/功能增刪建議.md` 第三批

## ⏭️ 下一步

1. 先看 `E:\習慣地瓜\簽章\` 有沒有 `anthropic-api-key.txt`；有就 `cd server && npm run eval`。
2. 使用者部署好伺服器後：填 `ShujiAIBaseURL`，Debug 測試區貼通行碼，用 Limrun（要點數）或真機走一遍六個入口。
3. 都過了 PR #6 轉正式、合併。

## 🗑️ 雜訊

- Swift 泛型函式裡不能宣告巢狀型別，第一次 CI 就死在這（已修）。
- server 兩份 tsconfig：`tsconfig.json` 只管 src（Worker 型別），`tsconfig.node.json` 管 test 和 eval。
- PR 才會觸發 CI，推分支不會。
