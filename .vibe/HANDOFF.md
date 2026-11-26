# Handoff: potato-b 已併 main（b4eb789），TestFlight 1.0（14）已上傳，等多米真機

> 2026-11-26 深夜。repo `E:\習慣地瓜\shuji`，分支 `potato-b` 已併 main（b4eb789，main CI run 45899049967 全綠），TestFlight 1.0（14）run 45899075225 已上傳。上一份 `.vibe/handoff/archive/2026-11-26-all-D.md`。
> 規劃與多米的決定：`docs/規劃-點數收費-多習慣-AI對手與犒賞-2026-11-26.md`（開頭寫了多米定的三件）。

## ✅ 做完的（都在 potato-b）
1. **地瓜換 B**（圖 1）：橫躺彎身、細根，記好了縱切攤開。只改 `Shuji/Views/HoldButton.swift` 的 PotatoArt／BShape；`PotatoArt.fit` 照位子塞滿。預覽 `E:\習慣地瓜\地瓜B-1126\預覽.html`。
2. **規劃加對手、擋對手、犒賞**：任務 8 多 rival／block／reward 三步，三選一可「先不用」。`TalkModel` 七步（offers 字典、choose／skip、back 照走過的路）。知識包搭建第八節、提示詞、`server/src/checks.ts`。Habit 多 rival／block／reward；種下去那頁列「擋住／做完」，今天頁記好後「給自己：…」，我的習慣頁可改。
3. **多習慣切換選單**：`AppState.others`（同時在養的其他習慣），`habit` 仍是現在看的；`Store.switchHabit／shelveHabit／addingHabit／maxHabits`（免費 2、完整版 5）。今天頁頂端習慣名稱＋向下箭頭的 Menu（切換、加一個、收起這個；別的沒記時一個小點）。`AddHabitView` 在 OnboardingView.swift。Habit 多 `name`（規劃打的想養什麼）。`ShujiTests/MultiHabitTests.swift` 八個測試。
4. **伺服器點數帳本**：`server/src/credits.ts`（costOf、StoreKit JWS 驗證）、`/v1/credits/balance`、`/v1/credits/redeem`、任務扣點與退點、402 no_credits。伺服器測試 134 個全過。

5. **app 端點數**（2026-11-26 深夜，commit eb0c894，已 push）：`Shuji/AI/Credits.swift`（CreditAccount 存 iCloud 鑰匙圈、Credits 查餘額／買／redeem 成功才 finish／啟動補送 unfinished）；`AIClient.serverPost` 共用簽章，伺服器那條 body 帶 account、讀 credits、402 → `Failure.noCredits`；失敗下面「買點數」（AIStatus、TalkView）、`CreditsSheet`、AI 頁與設定顯示「剩 N 點」、完整版頁加「更多習慣格」。`ShujiTests/CreditsTests.swift` 三個測試。

## ⚠️ 沒驗過的
- `credits.ts` 的 `APPLE_ROOT_G3_SHA256` 是憑記憶寫的 Apple Root CA - G3 指紋，**沙盒實買前要對 Apple PKI 頁面核一次**；錯了只會加點失敗，不會白送。
- 通知與小工具只跟著「現在看的那個習慣」。

## ⏭️ 下一步
1. ✅ CI run 45831160927 全綠（編譯、單元測試、伺服器、Domy 代號）；`testReplantUnfinishedSwapsBack` 改成多習慣的新行為（有格子就一起養）。
2. 季稽核還是「完整版」才能做（規劃表寫它扣 5 點，沒定要不要拿掉完整版限制，保守沒動）。
3. 沒買點數時 App Store 還沒有商品，買點數頁會顯示「連不到 App Store」。
4. **停下來問多米**：App Store Connect 建兩個消耗型商品（碰錢）；伺服器部署＋遠端 D1 跑 `schema.sql`（中文路徑下 wrangler deploy 會靜默失敗）。
5. 多米在 1.0（14）真機看 B 地瓜、七步規劃、切換選單（伺服器沒部署前點數不會動，電腦 Claude 照常）。

## 📌 定了的（別再問）
- 地瓜一律 B。收費＝習慣格子買斷＋AI 點數（新裝 20、30 點 NT$60、100 點 NT$150、電腦 Claude 不扣）。多習慣用切換選單，不強制只培養一個。
- 提交要指定檔名；不開 worktree；repo 是 PUBLIC，推之前問（這輪多米說了 push 並開做）。
