import Foundation

// 原型 index.html「計算」區的逐一對應。全部是純函式，today 由外面傳進來，方便測試。

extension AppState {
    func log(on k: DayKey) -> DayLog? { logs[k.string] }

    /// 做了的日子，由早到晚
    var doneKeys: [DayKey] {
        logs.compactMap { $0.value.t == .done ? DayKey($0.key) : nil }.sorted()
    }

    var lastDone: DayKey? { doneKeys.last }

    /// 「回來」：前一天沒有任何紀錄（不是做了、也不是請假），而且不是第一節
    func isReturn(_ k: DayKey, doneKeys ds: [DayKey]? = nil) -> Bool {
        let ds = ds ?? doneKeys
        guard let first = ds.first, first < k else { return false }
        return log(on: k.adding(-1)) == nil
    }

    /// 放手測試那兩週（已結束的）：不算漏掉
    func inFinishedLetGoWindow(_ k: DayKey) -> Bool {
        guard let r = letgoResult, let s = r.start, let e = r.end else { return false }
        return k >= s && k < e
    }

    struct Stats: Equatable {
        var nodes: Int
        var ret: Int
        var missed: Int
        var leaves: Int
        var leaveLeft: Int
    }

    func stats(today t: DayKey) -> Stats {
        let ds = doneKeys
        var missed = 0
        if let h = habit {
            var k = h.planted
            while k < t {
                if log(on: k) == nil && !inFinishedLetGoWindow(k) { missed += 1 }
                k = k.adding(1)
            }
        }
        let ret = ds.filter { isReturn($0, doneKeys: ds) }.count
        let m = t.monthPrefix
        let leaves = logs.filter { $0.key.hasPrefix(m) && $0.value.t == .leave }.count
        return Stats(nodes: ds.count, ret: ret, missed: missed, leaves: leaves,
                     leaveLeft: max(0, settings.leave - leaves))
    }

    /// 昨天往前數，連續幾天沒紀錄
    func consecutiveMissed(today t: DayKey) -> Int {
        guard let h = habit else { return 0 }
        var n = 0
        var k = t.adding(-1)
        while k >= h.planted && log(on: k) == nil {
            n += 1
            k = k.adding(-1)
        }
        return n
    }

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

    /// 舊資料的「障礙版」併進「不順的時候」（backup）。obstacle 留著不動，原型還讀得到。
    mutating func migrateFields() {
        guard var h = habit else { return }
        if h.backup.isEmpty, !h.obstacle.isEmpty {
            h.backup = h.obstacle
            habit = h
        }
    }

    struct Signals: Equatable {
        var s1: Bool
        var flatLow: Bool
        var s2: Bool
        var s3: Bool
        var n: Int
        var passCount: Int { [s1, s2, s3].filter { $0 }.count }
    }

    /// 三個「長好了嗎」訊號
    func signals() -> Signals {
        var s1 = false
        var flatLow = false
        if weekly.count >= 6 {
            let l = Array(weekly.suffix(3).map(\.avg))
            if let hi = l.max(), let lo = l.min() {
                s1 = hi - lo <= 0.5
                flatLow = s1 && l[2] < 3
            }
        }
        return Signals(s1: s1, flatLow: flatLow, s2: pressure == true, s3: letgoResult?.pass == true, n: weekly.count)
    }

    /// 放手測試開始前 14 天做了幾天
    func doneInLast14Days(today t: DayKey) -> Int {
        var n = 0
        for i in 1...14 where log(on: t.adding(-i))?.t == .done { n += 1 }
        return n
    }

    /// 停了超過兩週：上次做了之後過了 14 天以上。放手測試剛結束的那兩週不算停。
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
}
