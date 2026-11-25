import Foundation

// 資料結構 v2（.analytics/04-資料結構.md）。
// 每一筆都有自己的編號、按下去的世界標準時間與當時時區；原始紀錄不覆寫，撤銷是標記。
// 讀得到 v1（原生版第一版）與網頁原型的 JSON：讀進來就照 04「舊資料怎麼轉過來」轉成 v2。
// 每個欄位都用 decodeIfPresent 加預設值，缺 key、多 key 都不會讀失敗。

/// 世界標準時間的字串，例「2026-11-22T00:12:40Z」。存字串，不管誰用哪種日期格式解碼都讀得回來。
enum Stamp {
    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - 習慣

struct Habit: Codable, Equatable {
    /// 習慣編號。每天的紀錄、開始四問都用它指回來
    var id: String
    var floor: String
    var trigger: String
    var travelFloor: String
    /// 舊的「障礙版」，已併進 backup；留著是為了原型讀得到
    var obstacle: String
    /// 不順的時候
    var backup: String
    var why: String
    var planted: DayKey
    /// 種下去那一刻（世界標準時間）；舊資料是空
    var plantedAt: String?
    var tz: String?
    /// 種下去時預估幾天養成；舊的習慣是空
    var estimatedDays: Int?

    init(floor: String, trigger: String, planted: DayKey,
         travelFloor: String = "", obstacle: String = "", backup: String = "", why: String = "",
         id: String = "", plantedAt: String? = nil, tz: String? = nil, estimatedDays: Int? = nil) {
        self.id = id
        self.floor = floor
        self.trigger = trigger
        self.planted = planted
        self.travelFloor = travelFloor
        self.obstacle = obstacle
        self.backup = backup
        self.why = why
        self.plantedAt = plantedAt
        self.tz = tz
        self.estimatedDays = estimatedDays
    }

    enum CodingKeys: String, CodingKey { case id, floor, trigger, travelFloor, obstacle, backup, why, planted, plantedAt, tz, estimatedDays }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        floor = try c.decodeIfPresent(String.self, forKey: .floor) ?? ""
        trigger = try c.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        travelFloor = try c.decodeIfPresent(String.self, forKey: .travelFloor) ?? ""
        obstacle = try c.decodeIfPresent(String.self, forKey: .obstacle) ?? ""
        backup = try c.decodeIfPresent(String.self, forKey: .backup) ?? ""
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        planted = try c.decodeIfPresent(DayKey.self, forKey: .planted) ?? DayKey.today()
        plantedAt = try c.decodeIfPresent(String.self, forKey: .plantedAt)
        tz = try c.decodeIfPresent(String.self, forKey: .tz)
        estimatedDays = try c.decodeIfPresent(Int.self, forKey: .estimatedDays)
    }
}

/// 設定頁裡改得到、會留改版紀錄的欄位
enum HabitFieldName: String, Codable, CaseIterable {
    case trigger, floor, backup, travelFloor, why
}

// MARK: - 每天的紀錄

enum LogKind: String, Codable {
    case done
    case leave
}

/// 某一天的狀態（從每天的紀錄讀出來給畫面用，不存）
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

/// 這一筆是怎麼記的
enum RecordSource: String, Codable {
    /// 在 app 裡按住
    case hold
    /// Siri、捷徑、動作按鈕
    case shortcut
    /// 補記昨天
    case backfill
    /// 從 v1 或原型轉過來的
    case imported
}

/// 記一節或請假，一天一筆。撤銷不刪，標 deletedAt。
struct DayRecord: Codable, Equatable, Identifiable {
    var id: String
    var habit: String
    var kind: LogKind
    /// 這一筆算哪一天（凌晨四點換日；補記是昨天）
    var day: DayKey
    var at: String?
    var tz: String?
    var source: RecordSource
    var reason: String?
    var deletedAt: String?

    var isActive: Bool { deletedAt == nil }

    init(id: String, habit: String, kind: LogKind, day: DayKey, at: String?, tz: String?,
         source: RecordSource, reason: String? = nil, deletedAt: String? = nil) {
        self.id = id
        self.habit = habit
        self.kind = kind
        self.day = day
        self.at = at
        self.tz = tz
        self.source = source
        self.reason = reason
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey { case id, habit, kind, day, at, tz, source, reason, deletedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        habit = try c.decodeIfPresent(String.self, forKey: .habit) ?? ""
        kind = LogKind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "done") ?? .done
        day = try c.decode(DayKey.self, forKey: .day)
        at = try c.decodeIfPresent(String.self, forKey: .at)
        tz = try c.decodeIfPresent(String.self, forKey: .tz)
        source = RecordSource(rawValue: try c.decodeIfPresent(String.self, forKey: .source) ?? "imported") ?? .imported
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

// MARK: - 開始四問

/// 一次「開始四問」。scores 是四個 1 到 7 的分數；平均不存，用的時候算。
struct WeeklyReview: Codable, Equatable, Identifiable {
    var id: String
    var habit: String
    var date: DayKey
    var scores: [Double]
    var at: String?
    var tz: String?

    var avg: Double { scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count) }

    init(date: DayKey, scores: [Double], id: String = "", habit: String = "", at: String? = nil, tz: String? = nil) {
        self.id = id
        self.habit = habit
        self.date = date
        self.scores = scores
        self.at = at
        self.tz = tz
    }

    enum CodingKeys: String, CodingKey { case id, habit, date, scores, at, tz }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        habit = try c.decodeIfPresent(String.self, forKey: .habit) ?? ""
        date = try c.decodeIfPresent(DayKey.self, forKey: .date) ?? DayKey.today()
        scores = try c.decodeIfPresent([Double].self, forKey: .scores) ?? []
        at = try c.decodeIfPresent(String.self, forKey: .at)
        tz = try c.decodeIfPresent(String.self, forKey: .tz)
    }
}

// MARK: - 時刻紀錄（壓力週、放手測試、旅行中）

struct Mark: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        /// 壓力週：有，照做了
        case pressureYes
        /// 壓力週：還沒遇到，或那週掉了
        case pressureNotYet
        case letgoStart
        case letgoEnd
        case travelOn
        case travelOff
        /// 提醒走到哪一段（Comeback.swift）。remindDaily 也用在使用者自己開關
        case remindDaily
        case remindAfterMiss
        case remindOff
    }

    var id: String
    /// 旅行中是生活狀態，不掛在習慣上（nil）
    var habit: String?
    var kind: Kind
    var day: DayKey
    var at: String?
    var tz: String?
    /// 放手：開始前 14 天記了幾天（判定當下的基準，照存）
    var prior: Int?
    /// 放手結束：回想做了幾天；記不清楚是 nil
    var recalled: Int?
    /// 放手結束：當時的判定
    var pass: Bool?

    init(id: String, habit: String?, kind: Kind, day: DayKey, at: String?, tz: String?,
         prior: Int? = nil, recalled: Int? = nil, pass: Bool? = nil) {
        self.id = id
        self.habit = habit
        self.kind = kind
        self.day = day
        self.at = at
        self.tz = tz
        self.prior = prior
        self.recalled = recalled
        self.pass = pass
    }
}

// MARK: - 開關句改版

struct HabitChange: Codable, Equatable, Identifiable {
    enum Via: String, Codable {
        /// 設定頁
        case settings
        /// AI 建議按了「放進…」
        case ai
        /// 從這週的田過去改的
        case week
    }

    var id: String
    var habit: String
    var field: HabitFieldName
    var from: String
    var to: String
    var day: DayKey
    var at: String?
    var tz: String?
    var via: Via
}

// MARK: - 觀察與試兩週（這週的田）

/// 一組天數：可以比的有幾天、裡面記了幾天
struct GroupCount: Codable, Equatable {
    var done: Int
    var days: Int

    static let zero = GroupCount(done: 0, days: 0)
    var rate: Double { days == 0 ? 0 : Double(done) / Double(days) }
}

/// 這週的田給她看的一個觀察。counts 照存「當時對她說了什麼」。
struct Insight: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        /// 平日／週末
        case weekend
        /// 旅行中／在家
        case travel
        /// 同一個請假原因
        case leaveReason
    }

    var id: String
    var habit: String
    var kind: Kind
    /// 那個回顧週的最後一天
    var week: DayKey
    var shownAt: String?
    var tz: String?
    var counts: [String: GroupCount]
    /// 比較少的那一組（weekend、weekday、travel）；同一個請假原因是 nil
    var low: String?
    /// 同一個請假原因：那個原因（她自己寫的字）
    var subject: String?
    var metricVersion: String
    /// 這次有沒有放進這週的田（3-9 C 的對照組才會 false；只有一個人，永遠 true）
    var shown: Bool
    /// 她選的原因；unanswered 是未填；不問原因的觀察是 nil
    var cause: String?
    /// 她選的做法；unanswered 是未填
    var action: String?
    /// 她寫的一句（小心保管）
    var note: String?
    /// 答應試兩週的話，試兩週的編號
    var trial: String?
}

struct Trial: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case running, done, stopped }

    var id: String
    var habit: String
    var observation: String
    var kind: Insight.Kind
    /// 要看的那一組：weekend 或 weekday
    var group: String
    /// 試的是哪個做法（觀察的 action 代碼）
    var change: String
    var start: DayKey
    /// 不含這天
    var end: DayKey
    var status: Status
    /// 觀察當時那一組的天數（照存）
    var before: GroupCount
    /// 到期時給她看的天數（照存）
    var after: GroupCount?
    var conclusion: String?
    var concludedAt: String?
}

/// 這週的田打開過（3-9 C 的週回顧打開率）
struct ReportSeen: Codable, Equatable, Identifiable {
    var id: String
    var habit: String
    var week: DayKey
    var at: String?
    var tz: String?
    /// review 送出開始四問之後；field 從田打開
    var from: String
}

// MARK: - 竹籃

/// 挖出來的地瓜。數字是挖出來那一刻給她看的（照存）；habit 指回原始紀錄
struct Potato: Codable, Equatable {
    var id: String
    var habit: String?
    var floor: String
    var trigger: String
    var nodes: Int
    var ret: Int
    var days: Int
    var planted: DayKey
    var dug: DayKey

    init(floor: String, trigger: String, nodes: Int, ret: Int, days: Int, planted: DayKey, dug: DayKey,
         id: String = "", habit: String? = nil) {
        self.id = id
        self.habit = habit
        self.floor = floor
        self.trigger = trigger
        self.nodes = nodes
        self.ret = ret
        self.days = days
        self.planted = planted
        self.dug = dug
    }

    enum CodingKeys: String, CodingKey { case id, habit, floor, trigger, nodes, ret, days, planted, dug }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        habit = try c.decodeIfPresent(String.self, forKey: .habit)
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

// MARK: - 畫面用的讀法（從時刻紀錄讀出來，不存）

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

/// 放手測試結束。days 是回想的天數；記不清楚時 recalled 是 nil、days 是 0。
struct LetGoResult: Decodable, Equatable {
    var days: Int
    var prior: Int
    var pass: Bool
    var start: DayKey?
    var end: DayKey?
    var recalled: Int?

    init(days: Int, prior: Int, pass: Bool, start: DayKey? = nil, end: DayKey? = nil) {
        self.days = days
        self.prior = prior
        self.pass = pass
        self.start = start
        self.end = end
        self.recalled = days
    }

    /// 從時刻紀錄讀出來用。記不清楚時 recalled 是 nil
    init(recalled: Int?, prior: Int, pass: Bool, start: DayKey?, end: DayKey?) {
        self.days = recalled ?? 0
        self.recalled = recalled
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
        recalled = days
    }
}

// MARK: - 設定

struct Settings: Codable, Equatable {
    var sound: Bool = true
    /// 0 是星期日
    var reviewDay: Int = 0
    /// 每月可請假次數（2026-11-25 起不擋、不顯示，留著讀舊檔）
    var leave: Int = 2
    /// 收工檢查（原生版才有）：預設關
    var check: Bool = false
    var checkHour: Int = 21
    var checkMinute: Int = 0
    /// 這週的田：做完開始四問後顯示。預設開（回顧層可以關，書 3-6）
    var weekCard: Bool = true
    /// 跳過的理由（今天頁跳過時點的那一排）
    var skipReasons: [String] = Settings.defaultSkipReasons

    static let defaultSkipReasons = ["旅行", "生病", "太累", "太忙"]
    static let maxSkipReasons = 8
    static let maxSkipReasonLength = 8

    /// 去頭尾空白、截到 8 字、拿掉空的和重複的、最多 8 個
    static func cleanSkipReasons(_ list: [String]) -> [String] {
        var out: [String] = []
        for raw in list {
            let v = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxSkipReasonLength))
            if !v.isEmpty, !out.contains(v) { out.append(v) }
        }
        return Array(out.prefix(maxSkipReasons))
    }

    init() {}

    enum CodingKeys: String, CodingKey { case sound, reviewDay, leave, check, checkHour, checkMinute, weekCard, skipReasons }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        reviewDay = min(6, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .reviewDay) ?? 0)))
        leave = min(3, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .leave) ?? 2)))
        check = try c.decodeIfPresent(Bool.self, forKey: .check) ?? false
        checkHour = min(23, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .checkHour) ?? 21)))
        checkMinute = min(59, max(0, Int(try c.decodeIfPresent(Double.self, forKey: .checkMinute) ?? 0)))
        weekCard = try c.decodeIfPresent(Bool.self, forKey: .weekCard) ?? true
        let reasons: [String]? = try? c.decodeIfPresent([String].self, forKey: .skipReasons)
        skipReasons = reasons.map { Settings.cleanSkipReasons($0) } ?? Settings.defaultSkipReasons
    }
}

// MARK: - 整份資料

struct AppState: Codable, Equatable {
    static let schemaVersion = 2

    var v: Int = AppState.schemaVersion
    /// 目前種著的那一個
    var habit: Habit? = nil
    /// 挖出來的習慣（完整的開關句留著；紀錄照樣在 records 裡）
    var pastHabits: [Habit] = []
    var records: [DayRecord] = []
    var reviews: [WeeklyReview] = []
    var marks: [Mark] = []
    var changes: [HabitChange] = []
    var observations: [Insight] = []
    var trials: [Trial] = []
    var seen: [ReportSeen] = []
    /// 漏掉的那幾段和理由
    var gaps: [Gap] = []
    /// 竹籃每週問的那一句
    var checks: [BasketCheck] = []
    var basket: [Potato] = []
    var queue: [String] = []
    var justDug: Potato? = nil
    var settings: Settings = Settings()
    /// 測試區「往後 N 天」。正式版永遠是 0。
    var dayOffset: Int = 0

    init() {}

    enum CodingKeys: String, CodingKey {
        case v, habit, pastHabits, records, reviews, marks, changes, observations, trials, seen,
             gaps, checks, basket, queue, justDug, settings, dayOffset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = Int(try c.decodeIfPresent(Double.self, forKey: .v) ?? 1)
        guard version >= 2 || c.contains(.records) else {
            // v1 或原型：照舊的形狀讀，再轉成 v2
            self = try LegacyState(from: decoder).migrated(today: DayKey.today())
            return
        }
        v = AppState.schemaVersion
        habit = try c.decodeIfPresent(Habit.self, forKey: .habit)
        pastHabits = try c.decodeIfPresent([Habit].self, forKey: .pastHabits) ?? []
        records = try c.decodeIfPresent([Lenient<DayRecord>].self, forKey: .records)?.compactMap(\.value) ?? []
        reviews = try c.decodeIfPresent([WeeklyReview].self, forKey: .reviews) ?? []
        marks = try c.decodeIfPresent([Lenient<Mark>].self, forKey: .marks)?.compactMap(\.value) ?? []
        changes = try c.decodeIfPresent([Lenient<HabitChange>].self, forKey: .changes)?.compactMap(\.value) ?? []
        observations = try c.decodeIfPresent([Lenient<Insight>].self, forKey: .observations)?.compactMap(\.value) ?? []
        trials = try c.decodeIfPresent([Lenient<Trial>].self, forKey: .trials)?.compactMap(\.value) ?? []
        seen = try c.decodeIfPresent([Lenient<ReportSeen>].self, forKey: .seen)?.compactMap(\.value) ?? []
        gaps = try c.decodeIfPresent([Lenient<Gap>].self, forKey: .gaps)?.compactMap(\.value) ?? []
        checks = try c.decodeIfPresent([Lenient<BasketCheck>].self, forKey: .checks)?.compactMap(\.value) ?? []
        basket = try c.decodeIfPresent([Potato].self, forKey: .basket) ?? []
        queue = try c.decodeIfPresent([String].self, forKey: .queue) ?? []
        justDug = try c.decodeIfPresent(Potato.self, forKey: .justDug)
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        dayOffset = Int(try c.decodeIfPresent(Double.self, forKey: .dayOffset) ?? 0)
    }
}

/// 陣列裡某一筆讀不出來就跳過，不讓整份資料讀失敗
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - v1 與原型的形狀

/// v1（原生版第一版）與網頁原型存的 JSON。只用來讀舊資料，讀完就轉成 v2。
struct LegacyState: Decodable {
    var habit: Habit?
    var logs: [String: DayLog] = [:]
    var weekly: [WeeklyReview] = []
    var basket: [Potato] = []
    var queue: [String] = []
    var pressure: Bool?
    var letgo: LetGo?
    var letgoResult: LetGoResult?
    var justDug: Potato?
    var travelEndedOn: DayKey?
    var settings: Settings = Settings()
    var dayOffset: Int = 0
    var travel: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case habit, logs, weekly, basket, queue, pressure, letgo, letgoResult, justDug, travelEndedOn, settings, dayOffset, travel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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

    /// 照 04「舊資料怎麼轉過來」轉成 v2。編號照日期組，同一份轉兩次結果一樣。
    /// today：原本沒有日期的紀錄（壓力週、旅行中開著）掛在這一天。
    func migrated(today t: DayKey) -> AppState {
        var s = AppState()
        s.settings = settings
        s.dayOffset = dayOffset
        s.queue = queue

        var hid = "hab-v1-orphan"
        if var h = habit {
            if h.id.isEmpty { h.id = "hab-v1-\(h.planted.string)" }
            if h.backup.isEmpty, !h.obstacle.isEmpty { h.backup = h.obstacle }
            hid = h.id
            s.habit = h
        }

        s.records = logs
            .compactMap { key, log -> DayRecord? in
                guard let k = DayKey(key) else { return nil }
                return DayRecord(id: "rec-v1-\(key)", habit: hid, kind: log.t, day: k, at: nil, tz: nil,
                                 source: .imported, reason: log.t == .leave ? (log.reason ?? "") : nil)
            }
            .sorted { $0.day < $1.day }

        s.reviews = weekly.enumerated().map { i, w in
            WeeklyReview(date: w.date, scores: w.scores, id: "rev-v1-\(w.date.string)-\(i)", habit: hid)
        }

        if let p = pressure {
            s.marks.append(Mark(id: "mark-v1-pressure", habit: hid, kind: p ? .pressureYes : .pressureNotYet,
                                day: t, at: nil, tz: nil))
        }
        if let r = letgoResult {
            if let start = r.start {
                s.marks.append(Mark(id: "mark-v1-letgoStart-\(start.string)", habit: hid, kind: .letgoStart,
                                    day: start, at: nil, tz: nil, prior: r.prior))
            }
            let end = r.end ?? t
            s.marks.append(Mark(id: "mark-v1-letgoEnd-\(end.string)", habit: hid, kind: .letgoEnd,
                                day: end, at: nil, tz: nil, prior: r.prior, recalled: r.days, pass: r.pass))
        }
        if let lg = letgo {
            s.marks.append(Mark(id: "mark-v1-letgoStart-\(lg.start.string)", habit: hid, kind: .letgoStart,
                                day: lg.start, at: nil, tz: nil, prior: lg.prior))
        }
        if let e = travelEndedOn {
            s.marks.append(Mark(id: "mark-v1-travelOff-\(e.string)", habit: nil, kind: .travelOff, day: e, at: nil, tz: nil))
        }
        if travel {
            s.marks.append(Mark(id: "mark-v1-travelOn", habit: nil, kind: .travelOn, day: t, at: nil, tz: nil))
        }
        // 照日期排；同一天照上面加進去的順序（結束一次放手、同一天又開始一次，順序不能顛倒）
        s.marks = s.marks.enumerated()
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
            .map(\.element)

        s.basket = basket.enumerated().map { i, p in
            var q = p
            if q.id.isEmpty { q.id = "pot-v1-\(p.planted.string)-\(p.dug.string)-\(i)" }
            return q
        }
        if var j = justDug {
            if j.id.isEmpty { j.id = s.basket.first(where: { $0.planted == j.planted && $0.dug == j.dug })?.id ?? "pot-v1-justdug" }
            s.justDug = j
        }
        return s
    }
}
