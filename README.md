# 薯記

一次只種一個習慣的 iPhone app。把一個新動作接在生活裡每天一定會發生的瞬間後面（「如果刷完牙，我就讀一頁書」），做完就按住一秒半，地瓜藤長一節。每週做一次「開始四問」看它有沒有變成自動的；三個訊號過兩個，就把地瓜挖出來收進竹籃，種下一個。

只數做了的，不數連續。漏掉的日子不會讓藤枯掉，回來的那一節會開花。

## 這個 repo 裡有什麼

```
index.html              原型（網頁版，可以直接用手機 Safari 開）
Shuji.xcodeproj         Xcode 專案（Xcode 16 以上）
Shuji/                  原生 app 程式
  App/                  進入點、通知、音效、觸覺、色票
  Core/                 日期、資料模型、計算、狀態容器、示範資料（不碰 UI，可單獨測）
  Views/                田、今天、設定三頁，首次設定，各種彈出卡，地瓜藤畫布
  Assets.xcassets       圖示、主色
  PrivacyInfo.xcprivacy 隱私清單（不蒐集任何資料）
ShujiTests/             單元測試，標準答案是用 Node 跑原型的 JS 算出來的
docs/功能增刪建議.md     原生版之後要補、要砍的東西
.github/workflows/      GitHub Actions：在 macOS 上建置、跑測試、打包未簽名 IPA
```

## 怎麼跑

### 有 Mac

1. 用 Xcode 16 以上打開 `Shuji.xcodeproj`。
2. 選一台模擬器或接上 iPhone，按執行。
3. 要裝到真機，在 Signing & Capabilities 選自己的 Team，Xcode 會自動處理簽章。

跑測試：`Cmd+U`，或在終端機：

```bash
xcodebuild test -project Shuji.xcodeproj -scheme Shuji -destination 'platform=iOS Simulator,name=iPhone 16'
```

### 沒有 Mac

跟洋蔥地圖那邊一樣，三條路：

A. **GitHub Actions 產未簽名 IPA，自己裝。** 這個 repo 的 workflow 會在 macOS 機器上建置、跑測試，然後把 `Shuji-unsigned.ipa` 放在 Artifacts 裡。push 上去等大約十分鐘，下載後在 Windows 用 Sideloadly 或 AltStore，用 Apple ID 簽章裝到 iPhone。免費帳號七天要重簽，付費開發者帳號一年。自己玩用這條。

B. **Codemagic 自動簽章上 TestFlight。** 有付費開發者帳號就走這條，給別人測、之後上架都順。Codemagic 連 App Store Connect 的 API key，每次 push 直接出現在 TestFlight。

C. **GitHub Actions 自備憑證簽章。** 把 p12 跟 provisioning profile 放進 repo 的 Secrets，workflow 多一段簽章與上傳。省 Codemagic 的錢，設定比較煩。

第一次跑 CI 多半要修 CI 本身（模擬器名稱、Xcode 版本），這很正常。

## 資料

- 存在手機裡的 `Application Support/Shuji/state.json`，會跟著 iPhone 的 iCloud 備份走。
- 格式跟原型 `index.html` 存在 localStorage 的 JSON 一模一樣。原型「匯出備份」複製出來的那段文字，貼進 app 的「設定 → 從備份還原」就能接著用；反過來也可以。
- 挖地瓜那一刻會自動寫一份備份到 app 的 Documents，在「檔案」app 裡「我的 iPhone → 薯記」找得到。
- 凌晨四點換日，跟原型一樣。

## 原生版跟原型不同的地方

- 「收工檢查」真的能開了：一天最多一則通知，只在那天還沒記的時候響，記了就不響。預設關。
- 測試區只在 Debug 建置裡有，正式版沒有。「全部清除」也只在測試區，正式版照原型不給清；要重來就刪掉 app 重裝。
- 放手測試那兩週不會被算成「漏掉」，測試剛結束也不會跳「停了一陣子」。原型會。
- 停了一陣子那頁的第三列「旁邊有更近的東西搶走了嗎？」會捲到「讓開始更容易」那張卡。原型捲錯地方。
- 觸覺用 Taptic（按下、按滿、開花三種），聲音用 AVAudioEngine 合成，跟靜音鍵走，app 裡沒有聲音開關。
- 匯出備份改成分享檔案，也可以複製成文字。
- 「為了什麼」會出現在「停了一陣子」那頁；「不順的時候」會出現在連漏兩天的提示下面。原型存了但沒顯示。
- 「障礙版」和「備用開關」合成一個「不順的時候」欄位；「讓開始更容易」三條從設定頁搬到「卡住了」那頁。
- 回顧日之後三天內都看得到「開始四問」連結；設定頁「節奏」說明了凌晨四點換日。

其他文案、數字、流程照原型，一字沒改。細節在 `docs/功能增刪建議.md`。
