# Handoff: 地瓜 B、規劃加對手與犒賞、多習慣切換選單、伺服器點數帳本；剩 app 端點數

> 2026-11-26 深夜。repo `E:\習慣地瓜\shuji`，分支 `potato-b`（從 main cb0d48b 開出，已 push，沒併 main）。上一份 `.vibe/handoff/archive/2026-11-26-all-D.md`。
> 規劃與多米的決定：`docs/規劃-點數收費-多習慣-AI對手與犒賞-2026-11-26.md`（開頭寫了多米定的三件）。

## ✅ 做完的（都在 potato-b）
1. **地瓜換 B**（圖 1）：橫躺彎身、細根，記好了縱切攤開。只改 `Shuji/Views/HoldButton.swift` 的 PotatoArt／BShape；`PotatoArt.fit` 照位子塞滿。預覽 `E:\習慣地瓜\地瓜B-1126\預覽.html`。
2. **規劃加對手、擋對手、犒賞**：任務 8 多 rival／block／reward 三步，三選一可「先不用」。`TalkModel` 七步（offers 字典、choose／skip、back 照走過的路）。知識包搭建第八節、提示詞、`server/src/checks.ts`。Habit 多 rival／block／reward；種下去那頁列「擋住／做完」，今天頁記好後「給自己：…」，我的習慣頁可改。
3. **多習慣切換選單**：`AppState.others`（同時在養的其他習慣），`habit` 仍是現在看的；`Store.switchHabit／shelveHabit／addingHabit／maxHabits`（免費 2、完整版 5）。今天頁頂端習慣名稱＋向下箭頭的 Menu（切換、加一個、收起這個；別的沒記時一個小點）。`AddHabitView` 在 OnboardingView.swift。Habit 多 `name`（規劃打的想養什麼）。`ShujiTests/MultiHabitTests.swift` 八個測試。
4. **伺服器點數帳本**：`server/src/credits.ts`（costOf、StoreKit JWS 驗證）、`/v1/credits/balance`、`/v1/credits/redeem`、任務扣點與退點、402 no_credits。伺服器測試 134 個全過。

## ⚠️ 沒驗過的
- **Swift 全部沒在本機編譯**：CI run 45826961566（含 2、3）在排 macOS 機器。下一個會話先看 `gh run list --branch potato-b`，紅了照 log 修。
- `credits.ts` 的 `APPLE_ROOT_G3_SHA256` 是憑記憶寫的 Apple Root CA - G3 指紋，**沙盒實買前要對 Apple PKI 頁面核一次**；錯了只會加點失敗，不會白送。
- 通知與小工具只跟著「現在看的那個習慣」。

## ⏭️ 下一步：app 端點數（多米已點頭「收費照規劃做」）
1. 匿名帳號：UUID 存 iCloud 鑰匙圈（kSecAttrSynchronizable），`AIClient` 送伺服器的 body 加 `account`（bridge 那條不用）。
2. 回應的 `credits` 存起來，AI 頁、付費頁顯示「剩 N 點」；402 `no_credits` 跳點數購買頁。
3. `Purchases`：加消耗型 `org.domyweb.shuji.credits30`（NT$60）、`credits100`（NT$150），買完把 `Transaction.jwsRepresentation` 送 `/v1/credits/redeem`，成功才 `finish()`；啟動時把沒 finish 的再送一次。完整版文案改成「更多習慣格（同時養到 5 個）」，Product ID 不變。
4. **停下來問多米**：App Store Connect 建兩個消耗型商品（碰錢）；伺服器部署＋遠端 D1 跑 `schema.sql`（中文路徑下 wrangler deploy 會靜默失敗）。
5. 之後：多米真機看 B 地瓜、七步規劃、切換選單；併 main、出 TestFlight。

## 📌 定了的（別再問）
- 地瓜一律 B。收費＝習慣格子買斷＋AI 點數（新裝 20、30 點 NT$60、100 點 NT$150、電腦 Claude 不扣）。多習慣用切換選單，不強制只培養一個。
- 提交要指定檔名；不開 worktree；repo 是 PUBLIC，推之前問（這輪多米說了 push 並開做）。
