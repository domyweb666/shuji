# Handoff: QC-0004 五筆都寫完，今天頁照方向 C 重畫剛推上去，還沒編譯驗證

> 產出時間：2026-11-24
> repo：`E:\習慣地瓜\shuji`（外層 `E:\習慣地瓜` 不是 git repo）
> 分支：`qc-0004`，從 origin/main 3243e9a 開，未併 main、沒開 PR、沒出 TestFlight

## ✅ 這次完成了什麼

- #31、#32：完整版、什麼時候不適合用，打開就是整頁（`SheetFrame(full: true)`）。
- #33：田分兩層，第一層只留三條訊號與開始四問，其他推進去（`FieldView(part:)`、`Route`）。
- #34：設定照準則 3-3、3-4 重排，接 VeggieKit 1.0.1；開關句搬到 `SentenceView.swift`。
- #30 前半：紅框三段字拿掉、藤上移。以上四項 CI 45310439389 全過（106 個測試），模擬器看過大部分。
- `RootView`：外層 NavigationStack；翻頁從 TabView(.page) 換成橫向 ScrollView。
- #30 後半：多米選了畫布方向 C「按那顆地瓜」，寫完在 d81b094，`check-ui-tokens` 過。

## 🚧 還沒做完 / 待決定

- d81b094 的 CI（run 45313818829）交接當下還在跑，**Swift 是盲寫的，沒看過能不能編、也沒看過畫面**。
- 左右滑只能真機判。模擬器合成拖曳從田、設定滑回來 1/6 成功，原本的 TabView 用同一支腳本也多半失敗。備案：外層加 DragGesture（合成拖曳 10/10，但沒驗會不會擋上下捲，沒放進去）。
- 沒看過：設定頁購買、支援、關於三區的圖示；家族頁從設定推進去；完整版、不適合從設定列點進去。
- 等多米：Anthropic 金鑰（`npx wrangler secret put ANTHROPIC_API_KEY`，多米自己跑）；放好後才把 `ShujiAIBaseURL` 填進 Info.plist（值在 deploy-server 分支）。QC-0004 沒有這項，多米點頭才做。
- 等多米：Apple ID（評分、分享列）、隱私權政策網址；準則要「清除所有資料」，但 2026-11-07 定過正式版不給，沒加。
- 芹查設定把路徑連引號存成 `"E:\習慣地瓜"`，所以說「不是認得的 app」；沒動，已告訴多米。

## 📌 關鍵決策

- 今天頁：方向 C。沒有「今天」大標題，日期一行＋開關句當標題；字都在土面上，土裡只有地瓜上的字；撤銷、請假、補記都在右上角 ⋯。
- 按著地瓜脹大 8%、外圈跑滿 1.5 秒；減少動態時不脹。手勢與時間沒改。
- 單子要一次 commit，實際是多筆（驗證時又修），已告訴多米。

## 📂 下個會話最重要的檔案

- `Shuji/Views/TodayView.swift`、`HoldButton.swift`（PotatoBody、PotatoSeal、HoldButton）、`VineView.swift`
- `Shuji/Views/RootView.swift`、`tools/check-ui-tokens.mjs`
- `.uiux/閘門紀錄.md`；畫布 https://claude.ai/artifact/13zweNPDDmp2J9fDrm1Dq2
- `~/.claude/projects/E------/memory/limrun-cloud-simulator.md`、`tools/limrun/test.mjs`（按 1.8 秒的寫法）

## ⏭️ 下一步從哪繼續

1. `git fetch`，確認在 `qc-0004`。`gh run view 45313818829` 看結果；紅的就 `gh run view 45313818829 --log-failed` 找 `error:` 修。
2. 綠了做工作包 B，再更新 `E:\習慣地瓜\QC-0004-截圖\01-今天.jpg`。
3. 全過才問多米要不要併 main 出 TestFlight（這兩件都要他點頭）。

## 🧩 剩下的工作（工作包）

- [ ] A：讓 d81b094 編得過｜ios.yml 全綠、106 個測試過｜上面五個 Swift 檔｜無
- [ ] B：Limrun 看今天頁各狀態（還沒記、按著、記好、請假、放手中、久停、記好加四問提醒、連漏兩天、長句子 40 字），淺色深色各一輪｜不用捲、地瓜和外圈不被分頁列遮、字不壓在土上、最後一節的根連到地瓜、外圈從正上方順時針跑｜同上｜依賴 A
- [ ] C：補看設定頁下半三區圖示、家族頁、兩張彈出頁從列點進去｜都有畫、都推得進去｜SettingsView.swift｜依賴 A，可跟 B 同一台機器

## 🗑️ 這次會話的雜訊

- 資料夾沒開錯，別再查芹查那句話。
- `feel-guide` 已經整條併進 main，不要從它開工。
