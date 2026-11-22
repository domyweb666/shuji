import Foundation

/// 一眼層的字（.analytics/07 字串表 G-1 到 G-9）。小工具跟 app 共用，所以放在 Shared。
/// 改字只改這裡；大括號是填空。
enum GlanceCopy {
    enum ID: String, CaseIterable {
        case todaySub = "G-1"
        case todaySubFirst = "G-1n"
        case widgetDone = "G-2"
        case widgetNone = "G-3"
        case widgetNoneFirst = "G-3n"
        case widgetLeave = "G-4"
        case widgetLetGo = "G-5"
        case widgetDug = "G-6"
        case widgetEmpty = "G-7"
        case siriDone = "G-8"
        case siriReturn = "G-9"
    }

    static let table: [ID: String] = [
        .todaySub: "{date} · 第 {n} 節",
        .todaySubFirst: "{date}",
        .widgetDone: "今天記了 · 第 {n} 節",
        .widgetNone: "今天還沒記 · 已長 {n} 節",
        .widgetNoneFirst: "今天還沒記",
        .widgetLeave: "今天請假",
        .widgetLetGo: "放手測試中，不用記",
        .widgetDug: "挖出來了，種下一個",
        .widgetEmpty: "還沒種東西",
        .siriDone: "記好了。{floor}，第 {n} 節。",
        .siriReturn: "回來了。{floor}，第 {n} 節。",
    ]

    static func t(_ id: ID, _ args: [String: String] = [:]) -> String {
        var s = table[id] ?? ""
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    /// G-1 今天頁副標：還沒記過第一節時不寫「第 0 節」
    static func todaySub(date: String, nodes: Int) -> String {
        nodes > 0 ? t(.todaySub, ["date": date, "n": "\(nodes)"]) : t(.todaySubFirst, ["date": date])
    }

    /// G-3 小工具還沒記：一節都沒有時不寫數字
    static func widgetNone(nodes: Int) -> String {
        nodes > 0 ? t(.widgetNone, ["n": "\(nodes)"]) : t(.widgetNoneFirst)
    }
}
