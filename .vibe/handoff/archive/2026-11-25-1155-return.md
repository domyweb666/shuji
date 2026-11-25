# Handoff: 需求研究的兩批「回來」「放手」寫完，等 CI 綠、拍圖、給多米看

> 2026-11-25 11:55。repo `E:\習慣地瓜\shuji`，分支 `return-1125`（從 main 30c118c 開，已 push，**沒併 main、沒出 TestFlight**）。上一份見 `.vibe/handoff/archive/2026-11-25-testflight10.md`

## ✅ 寫完的（規格 `docs/回來與放手-規格.md`，由來 `docs/需求研究對照-2026-11-25.md`）
- Swift：回來卡、回來那一下（花放大、花瓣、地瓜寫「你回來了」）、停了一陣子的今天頁、提醒退場、田的時間卡（M18）、竹籃每週一句、長好門檻（四問平均 4 以上）、預估滿了寫「快長好了」。新檔 `Core/Comeback.swift`、`Core/UsualTime.swift`、`Views/BackSheet.swift`、`ShujiTests/ComebackTests.swift`。
- 伺服器任務 9：多收 ease、usual_time、gap_reasons（都可缺），vitest 126 綠。
- `.analytics` 02–08、兩份閘門紀錄、機制表、功能增刪建議都同步。

## 🚧 現況
- CI run 45541795122：app 編得過，只有 `WeekReviewTests.swift` 少三個參數；已修（d1b6365）。Swift 單元測試**還沒有任何一次跑完**。
- 新一輪 **run 45542873262**（d1b6365）剛排上。
- 模擬器一張都沒拍。真機沒驗。任務 9 新提示詞沒實跑模型、沒部署。

## 📌 定了的（別再問）
1. 多米 2026-11-25：「兩批都做」。沒先畫畫布，用模擬器實拍圖給他看（已跟他說）。
2. 沒選的照現況不動：每天制、小工具鎖完整版、完整版賣什麼。報告最後再問一次就好。
3. 不照研究做：藤縮、自訂換日、四問改兩週一次。
4. 回來卡同一段漏掉只問一次（避免一直漏的人每天被問）；收掉等於不說。理由不改「漏掉」，回來照樣開花。
5. 程式的判斷：停了一陣子跟 `longAbsence` 同算法；剛調回每天提醒的先待滿 14 天；竹籃跳過正在種、已排隊的。
6. 提交要指定檔名；不開 worktree；不併 main、不上 TestFlight，等多米看圖點頭。

## ⏭️ 下一步
1. `gh run view 45542873262 --json conclusion,jobs`。job was not acquired 就 `gh run rerun <id> --failed`。紅的照 `--log-failed` 修，`gh workflow run ios.yml --ref return-1125` 重跑。
2. 綠了：`gh run download <id> -n Shuji-simulator-app` 下到 scratchpad，跑 `node tools/limrun/states.mjs <zip> <輸出> back,todo,done,missed2,absent`（`back` 那組是新寫的，還沒跑過；狀態名與 AXLabel 可能要調）。Limrun 以分鐘計價，腳本自己會關。
3. 自己看每張（淺深色）：地瓜上的「你回來了」有沒有擠到、花放大有沒有被切、回來卡間距（8／12／20）、時間卡三個軸字、對答最後一句（`talk` 組第 4 步）變長有沒有折壞。
4. 圖拼好放 `E:\習慣地瓜\回來與放手-1125\`，給多米看。
5. 記憶 `shuji-ios-port-2026-11.md` 與 MEMORY.md 那一行更新。

## 🧩 剩下的工作
- [ ] A：CI 三個工作全綠｜run 綠｜ShujiTests、有錯的 Swift｜無
- [ ] B：拍圖、自看、修畫面｜back 組淺深色都看過｜tools/limrun/states.mjs、Views｜依賴 A
- [ ] C：給多米看圖加總報告｜圖在上面那個資料夾｜無程式｜依賴 B
- [ ] D（順手，可不做）：`server/src/checks.ts` 的 `wrongNumbers` 正則 `s*` 應是 `\s*`，「5 天」帶空格時沒被核對（舊 bug）

## ⚠️ 已知沒處理
- M18、checks、提醒三種 Mark 在 `.analytics/01-問題清單.md` 沒有題號；04 的新結構沒請多米過閘門 2。
- 調回每天提醒之後連漏到第 3 天，照安靜規則 6 又會安靜（沿用舊規則）。
