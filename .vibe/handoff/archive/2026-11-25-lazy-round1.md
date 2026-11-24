# Handoff: 懶人化（跳過、月曆可點、設定瘦身、AI 接電腦 CLI），等多米選畫布

> 2026-11-25。repo `E:\習慣地瓜\shuji`，分支 `lazy-1125`（已推，沒併 main，沒出 TestFlight）

## ✅ 做完
- 「開關句」→「我的習慣」、「開關」→「時機」、「收工檢查」→「每天提醒」、「請假」→「跳過」（AI 產出也換，`server/src/checks.ts` plainWording）。存檔格式沒動。
- 跳過一次：理由在設定可增刪，沒有每月次數。單子 `SkipSheet`／`SkipForm`，入口暫放今天頁 ⋯。旅行中開關拿掉，打開 app 會自動結束舊的旅行狀態。
- 月曆可點（`DaySheet`）：今天、昨天可改，更早只看。
- 設定拿掉旅行中、每月請假、週回顧日、這週的田；加跳過的理由、AI。
- AI：`server/bridge`（`cd server; npm run bridge`）＋ `Shuji/AI/Bridge.swift`、`AIHubView.swift`、`QRScanner.swift`。真的 CLI 跑過任務 7、2。
- CI run 45438034981 全綠；模擬器截圖 `E:\習慣地瓜\懶人化-1125\模擬器截圖.jpg`（`states.mjs ... lazy`）。

## 🚧 等多米
- 畫布 https://claude.ai/artifact/6Lb2CczhJG9BNGdpwhcz5u 四組選一：跳過位置、田的分析、AI 入口、設定。選了才重做分析頁與今天頁入口。**分析頁這次只改字，沒重做。**
- 要不要先併 main 出 TestFlight。

## ⚠️ 沒驗
- 真機：掃 QR、區域網路授權、防火牆、手機經 Wi-Fi 打到電腦。任務 1、3、4、6 沒用真 CLI 跑。
- 375 點寬手機月曆格 43.3 點。首次設定（還沒種）進不了設定，所以連不到 AI，要在 OnboardingView 加入口。
- 畫布沒有逐張開起來看。

## ⏭️ 下一步
1. 照多米選的做：田（先更新 `.analytics/06`、`07`）、今天頁入口、AI 選一句的半頁、Onboarding 的 AI 入口。
2. 設計哲學見記憶 feedback-lazy-design：少設定、先講答案、規則藏起來。
3. 畫布 AI 那組的「一直忘記、做起來太累…」選單是新流程，要接任務 4（找哪裡卡住）或新任務。
