import Foundation

/// 田的報表要的數字（畫面只負責畫）。只陳述：沒有完成率、沒有連續天數。

/// 月曆的一格
struct MonthDay: Equatable {
    enum Kind: Equatable { case none, done, back, leave }
    var day: DayKey
    var kind: Kind
}

struct MonthReport: Equatable {
    var year: Int
    var month: Int
    /// 1 號前面空幾格（星期日開頭）
    var lead: Int
    var days: [MonthDay]
    /// 記了幾天、回來幾次、請假幾天
    var done: Int
    var back: Int
    var leave: Int
}

/// 一週一條
struct WeekBarData: Equatable {
    var start: DayKey
    var done: Int
    var current: Bool
    /// 放手測試的週：那週本來就不記
    var letgo: Bool
}

extension AppState {
    /// back 是往前幾個月，0 是這個月。種下去之前的月份回 nil
    func monthReport(today t: DayKey, back: Int) -> MonthReport? {
        guard let h = habit else { return nil }
        let index = t.year * 12 + (t.month - 1) - back
        guard back >= 0, index >= h.planted.year * 12 + (h.planted.month - 1) else { return nil }
        let y = index / 12, m = index % 12 + 1
        let first = DayKey(year: y, month: m, day: 1)
        let nextFirst = DayKey(year: (index + 1) / 12, month: (index + 1) % 12 + 1, day: 1)
        let l = ledger(today: t)
        var days: [MonthDay] = []
        var done = 0, returns = 0, leave = 0
        for i in 0..<DayKey.days(from: first, to: nextFirst) {
            let d = first.adding(i)
            var kind = MonthDay.Kind.none
            if d >= h.planted, d <= t {
                if l.isDone(d) {
                    done += 1
                    kind = .done
                    if l.isReturn(d) {
                        kind = .back
                        returns += 1
                    }
                } else if l.isLeave(d) {
                    leave += 1
                    kind = .leave
                }
            }
            days.append(MonthDay(day: d, kind: kind))
        }
        return MonthReport(year: y, month: m, lead: first.weekday, days: days, done: done, back: returns, leave: leave)
    }

    /// 最近幾週各記了幾天，由舊到新，最後一條是這週（切法跟週回顧日一樣）
    func weekBars(today t: DayKey, count: Int = 8) -> [WeekBarData] {
        guard let h = habit else { return [] }
        let l = ledger(today: t)
        let last = lastReviewDay(today: t)
        var e = last == t ? t : last.adding(7)
        var rows: [WeekBarData] = []
        for i in 0..<count {
            if e < h.planted { break }
            let w = l.week(end: e)
            rows.append(WeekBarData(start: w.start, done: w.done, current: i == 0, letgo: w.letgo > 0 && w.done == 0))
            e = e.adding(-7)
        }
        return rows.reversed()
    }

    /// 最近 12 週，每個星期幾各記了幾天（0 是星期日）
    func weekdayTally(today t: DayKey) -> [Int] {
        var n = Array(repeating: 0, count: 7)
        let from = t.adding(-83)
        for d in ledger(today: t).doneDays where d >= from && d <= t { n[d.weekday] += 1 }
        return n
    }
}
