# Handoff: 多米選了跳過 A、田 B、設定 A；AI 改成貫穿流程，等他選對話樣式

> 2026-11-25 凌晨。repo `E:\習慣地瓜\shuji`，分支 `lazy-1125`（第一輪 33f9dd8 已推、CI 綠；沒併 main、沒出 TestFlight）
> 第一輪做了什麼、沒驗什麼：`.vibe/handoff/archive/2026-11-25-lazy-round1.md`

## 🏃 正在做（可能還沒 commit）
子代理在把「跳過 A、田 B、設定 A」寫進 app，改 `TodayView`、`Sheets`、`FieldView`、`SettingsView`、`Core/FieldReport`、新測試 `FieldReportTests`、`.analytics/06`、`states.mjs`。**接手先 `git status`**：有改動就跑 `node tools/check-ui-tokens.mjs`、commit、push、`gh workflow run ios.yml --ref lazy-1125`，綠了下載 `Shuji-simulator-app`，`node tools/limrun/states.mjs <zip> <輸出> lazy,field` 拍圖，每張都看過。`git status` 乾淨而且最新 commit 是 33f9dd8 之後只有文件，代表子代理沒寫完，照下面重派。

## 📌 多米定的（別再問）
1. 跳過：右上角文字鈕「跳過」，點理由就記好；記了或跳過後變「復原」。
2. 田：月曆｜分析兩面，分析一張卡答一題（畫布 FieldB、FieldFew）。
3. 設定：SetA，留每天提醒。
4. AI 貫穿流程、放在後台、只輔助他選：第一次打開就由 AI 問要養什麼 → 拆動作 → 規劃試幾天；週報由 AI 看過紀錄給選項；設定頁有「重新規劃習慣」。這推翻「首次設定按鈕式 AI」和閘門 0 的「週報不用模型」，實作時在 `.analytics/00`、`07` 記一筆；守住「系統說現象、原因與改法他選」，送 AI 的只有算好的數字。
5. 畫布 page `ai` 的 A、B 兩個入口都不採用。

## 🚧 等多米
- 選對話樣式：https://claude.ai/artifact/6Lb2CczhJG9BNGdpwhcz5u 的「5 AI 對話」，A 填空句（推薦）／B 一題一頁／C 聊天泡泡。A 到 C 可以點著走。畫布沒有逐張開起來看過。
- 出不出 TestFlight。

## ⏭️ 選完之後要做
- Onboarding 換成選定的樣式，接現有任務 7（`GuideView`、`server/src/tasks.ts`）；多一步「先試幾天」（7／14／30，存檔要加欄位 `trialDays`，decodeIfPresent；護欄禁「X 天養成」，只能講「先試」）；試完那天自動跳「再試／改小／換一個」。
- 沒連電腦時要有退路：先讓他連（AIHubView）或用內建選項自己填。等 AI 約 10 秒要有等待畫面（ChatWait）。
- 設定加「重新規劃習慣」（蓋掉目前的要先收進 pastHabits，`Store.plant` 已會做）。
- 週報：接一個新任務（或任務 5 復活），輸入只給天數，輸出 2–3 個改法選項；畫面照 ChatWeek。取代現有「這週的田」卡。
- 真機沒驗：掃 QR、區網授權、防火牆。任務 1、3、4、6 沒用真 CLI 跑。
