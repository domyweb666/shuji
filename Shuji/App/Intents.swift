import AppIntents
import Foundation

/// 「記一節」捷徑：接 Siri、捷徑 app、iPhone 15 Pro 以後的動作按鈕。
/// 動作按鈕要按住才觸發，手感跟 app 裡的按住一秒半接近，所以這是唯一准許從 app 外面記的入口。
/// 不開 app、不跳畫面，只回一句話。
struct LogNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "記一節"
    static let description = IntentDescription("做完最小一步之後記一節。今天記過、請假、放手測試中都不會重複記。")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // app 正在跑就用它的 Store，畫面才會馬上更新；沒在跑就自己開一個讀檔
        let store = Store.live ?? Store()
        let reply = Self.log(into: store)
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }

    /// 回一句給 Siri 唸的話。跟畫面上的狀態機同一個順序（Store.shortcutLog）。
    @MainActor
    static func log(into store: Store) -> String { store.shortcutLog() }
}

/// 讓 Siri 聽得懂「薯記記一節」，捷徑 app 也會自動列出來
struct ShujiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogNodeIntent(),
            phrases: [
                "\(.applicationName)記一節",
                "在\(.applicationName)記一節",
                "用\(.applicationName)記一節",
            ],
            shortTitle: "記一節",
            systemImageName: "leaf"
        )
    }
}
