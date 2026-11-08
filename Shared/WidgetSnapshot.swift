import Foundation

/// 給小工具看的一小份快照，放在 App Group 容器裡。
/// app 每次存檔順手寫一份；小工具只讀這個，不碰 state.json。
/// 小工具是被動看到的：開關句＋今天記了沒。沒有按鈕，記一節還是得進 app 按住。
struct WidgetSnapshot: Codable, Equatable {
    enum Status: String, Codable {
        /// 還沒種東西
        case empty
        /// 今天還沒記
        case none
        case done
        case leave
        /// 放手測試中，不用記
        case letgo
        /// 剛挖出來，還沒種下一個
        case dug
    }

    var trigger: String
    var floor: String
    var nodes: Int
    var status: Status
    /// 這份快照算的是哪一天（YYYY-MM-DD，凌晨四點換日）
    var day: String
    var updated: Date
    /// 小工具是完整版的功能。舊快照沒有這欄，讀成 nil，當沒買
    var full: Bool? = nil

    static let groupID = "group.org.domyweb.shuji"
    static let fileName = "widget.json"

    static func url() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    static func read(from url: URL? = WidgetSnapshot.url()) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func write(to url: URL? = WidgetSnapshot.url()) -> Bool {
        guard let url, let data = try? JSONEncoder().encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// 小工具畫面上現在該顯示什麼。快照寫的那天過了（換日），記了或請假都要變回「還沒記」。
    func display(today: DayKey) -> Status {
        if (status == .done || status == .leave) && day != today.string { return .none }
        return status
    }

    /// 預覽、還沒拿到資料時用
    static let sample = WidgetSnapshot(trigger: "起床喝完第一杯水", floor: "打開檔案寫一句", nodes: 12,
                                       status: .none, day: DayKey.today().string, updated: Date(), full: true)
}
