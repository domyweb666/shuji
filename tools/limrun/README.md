# Limrun 模擬器走一遍

沒有 Mac 的時候，用 Limrun 的雲端 iPhone 模擬器跑一遍薯記 iOS 版的主流程，每一步截圖，最後印一張過／沒過的清單。
抓得到的是功能有沒有壞：按了沒反應、畫面不對、資料沒留住、閃退。
抓不到的還是要真機：按住時的震動、藤長出來的動畫順不順、傾斜搖葉、收工檢查通知有沒有在對的時間跳、「檔案」app 裡看不看得到備份。

## 前提

- 這台電腦的 `~/.lim/config.yaml` 有 `api-key`（或設環境變數 `LIM_API_KEY`）。
- Limrun 帳號有點數或訂閱。沒有的話開機會被拒，錯誤訊息很清楚。
- Windows 上 `lim` CLI 每個指令會卡 15 秒，所以這裡直接用 `@limrun/api`。

## 跑法

1. 到 GitHub Actions 找最新一次綠的 run，下載 artifact `Shuji-simulator-app`，裡面是 `Shuji-simulator.app.zip`（通用架構的模擬器版 Debug 建置）。
   `gh run download <run id> -n Shuji-simulator-app -D ../../build-artifact`
2. 在這個資料夾 `npm install`。
3. `node test.mjs <Shuji-simulator.app.zip 的路徑>`

跑完截圖在 `shots/`，檔名就是步驟；`shots/results.json` 是每一條檢查的結果。模擬器用完會自己刪，開著是扣點的（每分鐘約兩點），一趟大約五到七分鐘。

## 它走的流程

首次設定兩步（最小一步、掛在哪裡）→ 種下去 → 短按一下不該記、按住一秒半才記 → 撤銷今天、按住時手指滑開 15 點也要算 → 田頁、設定頁 → 測試區載入示範資料 → 往後一天再按住 → 開始四問 → 關掉重開看資料還在 → 深色模式三頁 → 測試區全部清除回到首次設定。

## 它怎麼「按住」

用 `performActions` 的 `touchDown` → `wait` → `touchUp`，中心點從無障礙樹裡「按住一秒半，記一節」那個元素的 frame 算。
