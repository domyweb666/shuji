import Foundation

// 原型 index.html「計算」區的對應，改成從 v2 的紀錄讀。全部是純函式，today 由外面傳進來，方便測試。
// 「漏掉」「回來」「連漏」的定義照 .analytics/05-指標字典.md 的共用定義（C1 到 C11）。

extension AppState {
    // MARK: 目前這個習慣的紀錄（讀出來的，不存）

    var habitID: String? { habit?.id }

    /// 目前習慣、沒撤銷的每天紀錄
    var activeRecords: [DayRecord] {
        guard let id = habitID else { return [] }
        return records.filter { $0.habit == id && $0.isActive }
    }

    /// 某一天的狀態。同一天有兩筆有效紀錄時，取後面那筆
    var logs: [String: DayLog] {
        var d: [String: DayLog] = [:]
        for r in activeRecords { d[r.day.string] = DayLog(t: r.kind, reason: r.reason) }
        return d
    }

    func log(on k: DayKey) -> DayLog? {
        guard let id = habitID else { return nil }
        guard let r = records.last(where: { $0.habit == id && $0.isActive && $0.day == k }) else { return nil }
        return DayLog(t: r.kind, reason: r.reason)
    }

    /// 做了的日子，由早到晚
    var doneKeys: [DayKey] {
        Array(Set(activeRecords.filter { $0.kind == .done }.map(\.day))).sorted()
    }

    var lastDone: DayKey? { doneKeys.last }

    /// 目前習慣的開始四問，照日期排（同一天照做的順序）
    var weekly: [WeeklyReview] {
        guard let id = habitID else { return [] }
        return reviews.enumerated()
            .filter { $0.element.habit == id }
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
    }

    var habitMarks: [Mark] {
        guard let id = habitID else { return [] }
        return marks.filter { $0.habit == id }
    }

    /// 壓力週最後一次的回答：nil 還沒回答、false 還沒遇到或那週掉了、true 照做了
    var pressure: Bool? {
        guard let m = habitMarks.last(where: { $0.kind == .pressureYes || $0.kind == .pressureNotYet }) else { return nil }
        return m.kind == .pressureYes
    }

    var pressureDay: DayKey? {
        habitMarks.last(where: { $0.kind == .pressureYes || $0.kind == .pressureNotYet })?.day
    }

    /// 每一次放手測試。end 是結束那天（不含）；進行中是 nil。
    /// 原型轉過來、只有結束沒有開始的，沒有窗口。
    var letgoRuns: [LetGoRun] {
        var runs: [LetGoRun] = []
        var open: Mark? = nil
        for m in habitMarks where m.kind == .letgoStart || m.kind == .letgoEnd {
            if m.kind == .letgoStart {
                // 前一次沒結束又開始（不會發生）：當成在這次開始那天結束
                if let o = open { runs.append(LetGoRun(start: o.day, end: m.day, endMark: nil)) }
                open = m
            } else if let o = open {
                runs.append(LetGoRun(start: o.day, end: m.day, endMark: m))
                open = nil
            }
        }
        if let o = open { runs.append(LetGoRun(start: o.day, end: nil, endMark: nil)) }
        return runs
    }

    /// 放手測試進行中
    var letgo: LetGo? {
        guard let last = habitMarks.last(where: { $0.kind == .letgoStart || $0.kind == .letgoEnd }),
              last.kind == .letgoStart else { return nil }
        return LetGo(start: last.day, prior: last.prior ?? 0)
    }

    /// 最後一次放手測試的結果
    var letgoResult: LetGoResult? {
        guard let end = habitMarks.last(where: { $0.kind == .letgoEnd }) else { return nil }
        let start = letgoRuns.last(where: { $0.endMark?.id == end.id })?.start
        return LetGoResult(recalled: end.recalled, prior: end.prior ?? 0, pass: end.pass ?? false,
                           start: start, end: end.day)
    }

    /// 旅行中：最後一筆旅行紀錄是「開」
    var travel: Bool {
        marks.last(where: { $0.kind == .travelOn || $0.kind == .travelOff })?.kind == .travelOn
    }

    var travelEndedOn: DayKey? {
        marks.last(where: { $0.kind == .travelOff })?.day
    }

    /// 舊資料的「障礙版」併進「不順的時候」（backup）。obstacle 留著不動，原型還讀得到。
    mutating func migrateFields() {
        guard var h = habit else { return }
        if h.backup.isEmpty, !h.obstacle.isEmpty {
            h.backup = h.obstacle
            habit = h
        }
    }

    /// 一次建好目前習慣的每一天（共用定義）
    func ledger(today t: DayKey) -> Ledger { Ledger(state: self, today: t) }

    // MARK: 回來、漏掉、連漏

    /// 「回來」（M14）：前一天沒有紀錄、不是放手日、不是時區跳過日，而且不是第一節
    func isReturn(_ k: DayKey) -> Bool {
        ledger(today: k).isReturn(k)
    }

    struct Stats: Equatable {
        var nodes: Int
        var ret: Int
        var missed: Int
        var leaves: Int
        var leaveLeft: Int
    }

    func stats(today t: DayKey) -> Stats {
        let l = ledger(today: t)
        let ret = l.doneDays.filter { l.isReturn($0) }.count
        let m = t.monthPrefix
        let leaves = l.byDay.values.filter { $0.kind == .leave && $0.day.monthPrefix == m }.count
        return Stats(nodes: l.doneDays.count, ret: ret, missed: l.missedCount, leaves: leaves,
                     leaveLeft: max(0, settings.leave - leaves))
    }

    /// 昨天往前數，連續幾天漏掉（M13）。遇到放手測試就停。
    func consecutiveMissed(today t: DayKey) -> Int {
        guard habit != nil else { return 0 }
        return ledger(today: t).consecutiveMissed
    }

    // MARK: 週回顧

    /// 今天是週回顧日，而且這週還沒做過
    func needReview(today t: DayKey) -> Bool {
        guard habit != nil, t.weekday == settings.reviewDay else { return false }
        guard let last = weekly.last else { return true }
        return DayKey.days(from: last.date, to: t) >= 6
    }

    /// 這週的回顧日：今天，或今天之前最近的那一個
    func lastReviewDay(today t: DayKey) -> DayKey {
        let back = ((t.weekday - settings.reviewDay) + 7) % 7
        return t.adding(-back)
    }

    /// 回顧日當天到之後三天內，這週的四問還沒做。回顧日當天的判斷跟 needReview 一樣。
    func reviewPending(today t: DayKey) -> Bool {
        guard habit != nil else { return false }
        let r = lastReviewDay(today: t)
        guard DayKey.days(from: r, to: t) <= 3 else { return false }
        guard let last = weekly.last else { return true }
        return DayKey.days(from: last.date, to: r) >= 6
    }

    /// 這個回顧週做過開始四問了嗎（跟 reviewPending 同一個判斷：最後一次離回顧日不到 6 天）
    func reviewedThisWeek(today t: DayKey) -> Bool {
        guard let last = weekly.last else { return false }
        return DayKey.days(from: last.date, to: lastReviewDay(today: t)) < 6
    }

    // MARK: 長好了嗎

    struct Signals: Equatable {
        var s1: Bool
        var flatLow: Bool
        var s2: Bool
        var s3: Bool
        var n: Int
        /// S1 的細項：最近一次太久以前（> 14 天）
        var stale: Bool = false
        /// S1 的細項：最近三次橫跨超過 21 天
        var spread: Bool = false
        var passCount: Int { [s1, s2, s3].filter { $0 }.count }
    }

    /// 三個「長好了嗎」訊號（M6）。S1：至少 6 次、最近三次相差 0.5 以內、最近一次在 14 天內、三次橫跨 21 天以內
    func signals(today t: DayKey) -> Signals {
        let w = weekly
        var s1 = false
        var flatLow = false
        var stale = false
        var spread = false
        if w.count >= 6 {
            let last3 = Array(w.suffix(3))
            let l = last3.map(\.avg)
            if let hi = l.max(), let lo = l.min(), hi - lo <= 0.5 {
                stale = DayKey.days(from: last3[2].date, to: t) > 14
                spread = DayKey.days(from: last3[0].date, to: last3[2].date) > 21
                s1 = !stale && !spread
                flatLow = s1 && l[2] < 3
            }
        }
        return Signals(s1: s1, flatLow: flatLow, s2: pressure == true, s3: letgoResult?.pass == true,
                       n: w.count, stale: stale, spread: spread)
    }

    /// 打開 app 要自動問什麼（2026-11-24 多米定：四問和長好了嗎都不擺在田，時間到自己跳）。
    /// 種滿一週才開始問；放手中、剛挖出來、停了一陣子都不問。
    /// 四問：過了週回顧日、這週還沒做。長好了嗎照原本三個訊號，過兩個問要不要挖；
    /// 曲線走平之後才問壓力週，沒遇到就問要不要放手兩週。
    func autoAsk(today t: DayKey) -> AutoAsk? {
        guard let h = habit, justDug == nil, letgo == nil, !longAbsence(today: t),
              DayKey.days(from: h.planted, to: t) >= 7 else { return nil }
        if !reviewedThisWeek(today: t) { return .review }
        let sg = signals(today: t)
        if sg.passCount >= 2 { return .dig }
        guard sg.s1, !sg.flatLow else { return nil }
        if pressureDay.map({ DayKey.days(from: $0, to: t) >= AutoAsk.pressure.cooldown }) ?? true { return .pressure }
        if letgoResult.map({ DayKey.days(from: $0.end, to: t) >= AutoAsk.letgo.cooldown }) ?? true { return .letgo }
        return nil
    }

    /// 放手測試開始前 14 天做了幾天
    func doneInLast14Days(today t: DayKey) -> Int {
        let l = ledger(today: t)
        var n = 0
        for i in 1...14 where l.isDone(t.adding(-i)) { n += 1 }
        return n
    }

    /// 停了超過兩週（M15，習慣書）：上次做了之後過了 14 天以上。放手測試結束那天也當一個起點。
    func longAbsence(today t: DayKey) -> Bool {
        guard log(on: t) == nil, let last = lastDone else { return false }
        var anchor = last
        if let end = letgoResult?.end, end > anchor { anchor = end }
        return DayKey.days(from: anchor, to: t) > 14
    }

    /// 今天該做的最小一步：旅行中換旅行版
    var activeFloor: String {
        guard let h = habit else { return "" }
        if travel, !h.travelFloor.isEmpty { return h.travelFloor }
        return h.floor
    }

    /// 放手測試還剩幾天（14 天制）
    func letgoDaysLeft(today t: DayKey) -> Int? {
        guard let lg = letgo else { return nil }
        return 14 - DayKey.days(from: lg.start, to: t)
    }

    /// 收工檢查要不要排（08 安靜規則 6、7）：放手中、剛挖出來不排；連漏 3 天以上先不排，
    /// 今天記了（停的那段就結束了）馬上恢復，排明天那一則
    func checkShouldSchedule(today t: DayKey) -> Bool {
        guard settings.check, habit != nil, letgo == nil, justDug == nil else { return false }
        if log(on: t) != nil { return true }
        return consecutiveMissed(today: t) < 3
    }
}

/// 打開 app 自動跳出來的那一張
enum AutoAsk: String, Identifiable {
    case review, dig, pressure, letgo

    var id: String { rawValue }
    /// 跳過之後隔幾天再問
    var cooldown: Int { self == .review ? 1 : 14 }
}

/// 一次放手測試
struct LetGoRun: Equatable {
    var start: DayKey
    /// 結束那天（不含）；進行中是 nil
    var end: DayKey?
    var endMark: Mark?
}

/// 目前這個習慣的每一天，一次建好給所有指標用（.analytics/05 共用定義 C2 到 C11）
struct Ledger {
    let planted: DayKey
    let today: DayKey
    /// 有效紀錄（同一天兩筆取後面那筆），key 是 dayNumber
    let byDay: [Int: DayRecord]
    /// 記了一節的日子，由早到晚
    let doneDays: [DayKey]
    /// 放手日的範圍：[start, end)，dayNumber
    let letgoSpans: [(Int, Int)]
    /// 旅行中的範圍：[start, end]，dayNumber
    let travelSpans: [(Int, Int)]
    /// 停頓（C6）：每一段 [a, b]，dayNumber
    let pauses: [(Int, Int)]

    init(state s: AppState, today t: DayKey) {
        today = t
        planted = s.habit?.planted ?? t
        var by: [Int: DayRecord] = [:]
        for r in s.activeRecords { by[r.day.dayNumber] = r }
        byDay = by
        doneDays = by.values.filter { $0.kind == .done }.map(\.day).sorted()

        letgoSpans = s.letgoRuns.map { ($0.start.dayNumber, ($0.end ?? t.adding(1)).dayNumber) }

        var spans: [(Int, Int)] = []
        var on: Int? = nil
        for m in s.marks where m.kind == .travelOn || m.kind == .travelOff {
            if m.kind == .travelOn {
                if on == nil { on = m.day.dayNumber }
            } else if let a = on {
                spans.append((a, max(a, m.day.dayNumber)))
                on = nil
            }
        }
        if let a = on { spans.append((a, max(a, t.dayNumber))) }
        travelSpans = spans

        // 停頓：先找出每一段連續漏掉，再照個人節奏判斷
        var runs: [(Int, Int)] = []
        var start: Int? = nil
        let p = planted.dayNumber
        let end = t.dayNumber - 1
        if p <= end {
            for n in p...end {
                if Ledger.missed(n, by: by, letgo: letgoSpans) {
                    if start == nil { start = n }
                } else if let a = start {
                    runs.append((a, n - 1))
                    start = nil
                }
            }
            if let a = start { runs.append((a, end)) }
        }
        var found: [(Int, Int)] = []
        for (a, b) in runs where a - p >= 14 {
            let before = runs.filter { $0.0 >= a - 28 && $0.1 <= a - 1 }.map { $0.1 - $0.0 + 1 }.max() ?? 0
            let len = b - a + 1
            if len >= max(4, 2 * before) { found.append((a, b)) }
        }
        pauses = found
    }

    // 這幾個是 init 也要用的，寫成靜態

    private static func inSpans(_ n: Int, _ spans: [(Int, Int)]) -> Bool {
        spans.contains { n >= $0.0 && n < $0.1 }
    }

    private static func tzSkip(_ n: Int, by: [Int: DayRecord]) -> Bool {
        guard by[n] == nil, let a = by[n - 1], let b = by[n + 1],
              let za = a.tz, let zb = b.tz else { return false }
        return za != zb
    }

    private static func missed(_ n: Int, by: [Int: DayRecord], letgo: [(Int, Int)]) -> Bool {
        by[n] == nil && !inSpans(n, letgo) && !tzSkip(n, by: by)
    }

    // MARK: 共用定義

    func record(_ d: DayKey) -> DayRecord? { byDay[d.dayNumber] }
    func isDone(_ d: DayKey) -> Bool { byDay[d.dayNumber]?.kind == .done }
    func isLeave(_ d: DayKey) -> Bool { byDay[d.dayNumber]?.kind == .leave }
    func hasRecord(_ d: DayKey) -> Bool { byDay[d.dayNumber] != nil }

    /// C3 放手日
    func isLetGo(_ d: DayKey) -> Bool { Ledger.inSpans(d.dayNumber, letgoSpans) }

    /// C4 時區跳過日
    func isTimezoneSkip(_ d: DayKey) -> Bool { Ledger.tzSkip(d.dayNumber, by: byDay) }

    /// C5 漏掉的一天：種下那天到昨天，沒有紀錄、不是放手日、不是時區跳過日
    func isMissed(_ d: DayKey) -> Bool {
        d >= planted && d < today && Ledger.missed(d.dayNumber, by: byDay, letgo: letgoSpans)
    }

    /// C6 停頓裡的日子
    func inPause(_ d: DayKey) -> Bool {
        pauses.contains { d.dayNumber >= $0.0 && d.dayNumber <= $0.1 }
    }

    /// C11 旅行中的一天
    func isTravel(_ d: DayKey) -> Bool {
        travelSpans.contains { d.dayNumber >= $0.0 && d.dayNumber <= $0.1 }
    }

    /// 種下那天到昨天，漏掉幾天
    var missedCount: Int {
        guard planted < today else { return 0 }
        var n = 0
        var k = planted
        while k < today {
            if isMissed(k) { n += 1 }
            k = k.adding(1)
        }
        return n
    }

    /// M14 回來：前一天沒有紀錄、不是放手日、不是時區跳過日，而且不是第一節
    func isReturn(_ d: DayKey) -> Bool {
        guard let first = doneDays.first, first < d else { return false }
        let p = d.adding(-1)
        return !hasRecord(p) && !isLetGo(p) && !isTimezoneSkip(p)
    }

    /// M13 昨天往前連續漏掉幾天：遇到紀錄、放手日、種下之前就停；時區跳過日略過
    var consecutiveMissed: Int {
        var n = 0
        var k = today.adding(-1)
        while k >= planted {
            if hasRecord(k) || isLetGo(k) { break }
            if isTimezoneSkip(k) {
                k = k.adding(-1)
                continue
            }
            n += 1
            k = k.adding(-1)
        }
        return n
    }

    /// C10 可比較的一天（今天要有紀錄才算）
    func isComparable(_ d: DayKey) -> Bool {
        guard d >= planted, d <= today else { return false }
        if d == today && !hasRecord(d) { return false }
        if isLeave(d) || isLetGo(d) || isTimezoneSkip(d) || inPause(d) { return false }
        return true
    }
}
