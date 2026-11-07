import Foundation

// 資料形狀跟原型 index.html 存的 JSON 完全一樣（key 名、巢狀都相同），
// 所以原型「匯出備份」的那段文字，貼進這個 app 的「從備份還原」就能用。
// 每個欄位都用 decodeIfPresent 加預設值，缺 key、多 key 都不會讀失敗。

struct Habit: Codable, Equatable {
    var floor: String
    var trigger: String
    var travelFloor: String
    var obstacle: String
    var backup: String
    var why: String
    var planted: DayKey

    init(floor: String, trigger: String, planted: DayKey,
         travelFloor: String = "", obstacle: String = "", backup: String = "", why: String = "") {
        self.floor = floor
        self.trigger = trigger
        self.planted = planted
        self.travelFloor = travelFloor
        self.obstacle = obstacle
        self.backup = backup
        self.why = why
    }

    enum CodingKeys: String, CodingKey { case floor, trigger, travelFloor, obstacle, backup, why, planted }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        floor = try c.decodeIfPresent(String.self, forKey: .floor) ?? ""
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        travelFloor = try c.decodeIfPresent(String.self, forKey: .travelFloor) ?? ""
        obstacle = try c.decodeIfPresent(String.self, forKey: .obstacle) ?? ""
        backup = try c.decodeIfPresent(String.self, forKey: .backup) ?? ""
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        planted = try c.decodeIfPresent(DayKey.self, forKey: .planted) ?? DayKey.today()
    }
}

enum LogKind: String, Codable {
    case done
    case leave
}

struct DayLog: Codable, Equatable {
    var t: LogKind
    var reason: String?

    static let done = DayLog(t: .done, reason: nil)
    static func leave(_ reason: String) -> DayLog { DayLog(t: .leave, reason: reason) }

    enum CodingKeys: String, CodingKey { case t, reason }

    init(t: LogKind, reason: String?) {
        self.t = t
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .t) ?? "done"
        t = LogKind(rawValue: raw) ?? .done
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// 一次「開始四問」。scores 是四個 1 到 7 的分數，avg 是平均。
struct WeeklyReview: Codable, Equatable {
    var date: DayKey
    var scores: [Double]
    var avg: Double

    init(date: DayKey, scores: [Double]) {
        self.date = date
        self.scores = scores
        self.avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    enum CodingKeys: String, CodingKey { case date, scores, avg }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(DayKey.self, forKey: .date) ?? DayKey.today()
        scores = try c.decodeIfPresent([Double].self, forKey: .scores) ?? []
        if let a = try c.decodeIfPresent(Double.self, forKey: .avg) {
            avg = a
        } else {
            avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        }
    }
}

/// 挖出來的地瓜，收在竹籃裡
struct Potato: Codable, Equatable {
    var floor: String
    var trigger: String
    var nodes: Int
    var ret: Int
    var days: Int
    var planted: DayKey
    var dug: DayKey

    init(floor: String, trigger: String, nodes: Int, ret: Int, days: Int, planted: DayKey, dug: DayKey) {
        self.floor = floor
        self.trigger = trigger
        self.nodes = nodes
        self.ret = ret
        self.days = days
        self.planted = planted
        self.dug = dug
    }

    enum CodingKeys: String, CodingKey { case floor, trigger, nodes, ret, days, planted, dug }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        floor = try c.decodeIfPresent(String.self, forKey: .floor) ?? ""
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        nodes = Int(try c.decodeIfPresent(Double.self, forKey: .nodes) ?? 0)
        ret = Int(try c.decodeIfPresent(Double.self, forKey: .ret) ?? 0)
        days = Int(try c.decodeIfPresent(Double.self, forKey: .days) ?? 0)
        let fallback = DayKey.today()
        planted = try c.decodeIfPresent(DayKey.self, forKey: .planted) ?? fallback
        dug = try c.decodeIfPresent(DayKey.self, forKey: .dug) ?? fallback
    }
}

/// 放手測試進行中：start 是開始那天，prior 是開始前 14 天做了幾天
struct LetGo: Codable, Equatable {
    var start: DayKey
    var prior: Int

    init(start: DayKey, prior: Int) {
        self.start = start
        self.prior = prior
    }

    enum CodingKeys: String, CodingKey { case start, prior }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(DayKey.self, forKey: .start) ?? DayKey.today()
        prior = Int(try c.decodeIfPresent(Double.self, forKey: .prior) ?? 0)
    }
}

/// 放手測試結束。start / end 是原生版新加的（原型沒有），
/// 用來把那兩週從「漏掉」裡排除，也讓「藤還在」不會在測試剛結束時誤判。
struct LetGoResult: Codable, Equatable {
    var days: Int
    var prior: Int
    var pass: Bool
    var start: DayKey?
    var end: DayKey?

    init(days: Int, prior: Int, pass: Bool, start: DayKey? = nil, end: DayKey? = nil) {
        self.days = days
        self.prior = prior
        self.pass = pass
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey { case days, prior, pass, start, end }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = Int(try c.decodeIfPresent(Double.self, forKey: .days) ?? 0)
        prior = Int(try c.decodeIfPresent(Double.self, forKey: .prior) ?? 0)
        pass = try c.decodeIfPresent(Bool.self, forKey: .pass) ?? false
        start = try c.decodeIfPresent(DayKey.self, forKey: .start)
        end = try c.decodeIfPresent(DayKey.self, forKey: .end)
    }
}

struct Settings: Codable, Equatable {
    var sound: Bool = true
    /// 0 是星期日
    var reviewDay: Int = 0
    /// 每月可請假次數 0 到 3
    var leave: Int = 2
    /// 收工檢查（原生版才有）：預設關
    var check: Bool = false
    var checkHour: Int = 21
    var checkMinute: Int = 0

    init() {}

    enum CodingKeys: String, CodingKey { case sound, reviewDay, leave, check, checkHour, checkMinute }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        reviewDay = min(6, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .reviewDay) ?? 0)))
        leave = min(3, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .leave) ?? 2)))
        check = try c.decodeIfPresent(Bool.self, forKey: .check) ?? false
        checkHour = min(23, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .checkHour) ?? 21)))
        checkMinute = min(59, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .checkMinute) ?? 0)))
    }
}

struct AppState: Codable, Equatable {
    var v: Int = 1
    var habit: Habit? = nil
    /// key 是 "YYYY-MM-DD"。保留字串 key 是為了 JSON 跟原型一字不差。
    var logs: [String: DayLog] = [:]
    var weekly: [WeeklyReview] = []
    var basket: [Potato] = []
    var queue: [String] = []
    /// nil 還沒回答、false 還沒遇到、true 壓力週照做了
    var pressure: Bool? = nil
    var letgo: LetGo? = nil
    var letgoResult: LetGoResult? = nil
    var justDug: Potato? = nil
    var travelEndedOn: DayKey? = nil
    var settings: Settings = Settings()
    /// 測試區「往後 N 天」。正式版永遠是 0。
    var dayOffset: Int = 0
    var travel: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case v, habit, logs, weekly, basket, queue, pressure, letgo, letgoResult, justDug, travelEndedOn, settings, dayOffset, travel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = Int(try c.decodeIfPresent(Double.self, forKey: .v) ?? 1)
        habit = try c.decodeIfPresent(Habit.self, forKey: .habit)
        let rawLogs = try c.decodeIfPresent([String: DayLog].self, forKey: .logs) ?? [:]
        logs = rawLogs.filter { DayKey($0.key) != nil }
        weekly = try c.decodeIfPresent([WeeklyReview].self, forKey: .weekly) ?? []
        basket = try c.decodeIfPresent([Potato].self, forKey: .basket) ?? []
        queue = try c.decodeIfPresent([String].self, forKey: .queue) ?? []
        pressure = try c.decodeIfPresent(Bool.self, forKey: .pressure)
        letgo = try c.decodeIfPresent(LetGo.self, forKey: .letgo)
        letgoResult = try c.decodeIfPresent(LetGoResult.self, forKey: .letgoResult)
        justDug = try c.decodeIfPresent(Potato.self, forKey: .justDug)
        travelEndedOn = try c.decodeIfPresent(DayKey.self, forKey: .travelEndedOn)
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        dayOffset = Int(try c.decodeIfPresent(Double.self, forKey: .dayOffset) ?? 0)
        travel = try c.decodeIfPresent(Bool.self, forKey: .travel) ?? false
    }
}
