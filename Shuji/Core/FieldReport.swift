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
    /// 記了幾天、回來幾次、跳過幾天
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

    /// 正在過的這一週的最後一天（切法跟週回顧日一樣）
    func currentWeekEnd(today t: DayKey) -> DayKey {
        let last = lastReviewDay(today: t)
        return last == t ? t : last.adding(7)
    }

    /// 最近幾週各記了幾天，由舊到新，最後一條是這週
    func weekBars(today t: DayKey, count: Int = 8) -> [WeekBarData] {
        guard let h = habit else { return [] }
        let l = ledger(today: t)
        var e = currentWeekEnd(today: t)
        var rows: [WeekBarData] = []
        for i in 0..<count {
            if e < h.planted { break }
            let w = l.week(end: e)
            rows.append(WeekBarData(start: w.start, done: w.done, current: i == 0, letgo: w.letgo > 0 && w.done == 0))
            e = e.adding(-7)
        }
        return rows.reversed()
    }
}

// MARK: 分析：四張問句卡

/// 這週做得多嗎？
struct WeekCard: Equatable {
    var answer: String
    var rows: [WeekBarData]
    var lo: Int
    var hi: Int
    /// 左邊的軸字
    var from: String
}

/// 哪幾天常漏掉？
struct GapCard: Equatable {
    var answer: String
    var weekday: GroupCount
    var weekend: GroupCount
}

/// 不用想就會做了嗎？
struct EaseCard: Equatable {
    var answer: String
    var weekly: [WeeklyReview]
}

/// 都在什麼時候做？
struct TimeCard: Equatable {
    var answer: String
    var time: UsualTime
}

/// 跳過都因為什麼？
struct SkipCard: Equatable {
    var answer: String
    var list: String
}

/// 前三張都還不夠：什麼時候看得到。推不出日期就沒有進度條
struct FewCard: Equatable {
    var title: String
    var progress: Double?
}

/// 沒過門檻的那張是 nil，畫面就不出
struct FieldCards: Equatable {
    var week: WeekCard?
    var gap: GapCard?
    var ease: EaseCard?
    var time: TimeCard?
    var skips: SkipCard?
    var few: FewCard?
}

extension AppState {
    func fieldCards(today t: DayKey) -> FieldCards {
        guard habit != nil else { return FieldCards() }
        let l = ledger(today: t)
        var c = FieldCards(week: weekCard(l, today: t), gap: gapCard(l, today: t),
                           ease: easeCard(l, today: t), time: timeCard(today: t), skips: skipCard(l, today: t))
        if c.week == nil, c.gap == nil, c.ease == nil { c.few = fewCard(l, today: t) }
        return c
    }

    /// M3 對 M4，這週過完（回顧日當天）才比。放手的週、回來的週不比較
    private func weekCard(_ l: Ledger, today t: DayKey) -> WeekCard? {
        let e = currentWeekEnd(today: t)
        let w = l.week(end: e)
        guard w.letgo == 0, !l.isReturnWeek(end: e), let u = l.usualRange(before: e) else { return nil }
        let answer: String
        if e == t {
            // 沒有任何紀錄的週是空窗，不寫 0
            let n = w.hasRecord ? Copy.t(.f1days, ["n": w.done]) : Copy.t(.f1none)
            answer = u.lo == u.hi ? Copy.t(.f1same, ["n": n, "lo": u.lo]) : Copy.t(.f1a, ["n": n, "lo": u.lo, "hi": u.hi])
        } else {
            // 還沒到回顧日，跟一整週比一定偏少：只講到現在幾天
            answer = w.done > 0 ? Copy.t(.f1soFar, ["n": w.done]) : Copy.t(.f1notYet)
        }
        let rows = weekBars(today: t)
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八"]
        let from = digits.indices.contains(rows.count - 1) ? digits[rows.count - 1] : "\(rows.count)"
        return WeekCard(answer: answer, rows: rows, lo: u.lo, hi: u.hi, from: Copy.t(.f1from, ["k": from]))
    }

    /// M7：天數夠就出，差得夠多才說是哪一組
    private func gapCard(_ l: Ledger, today t: DayKey) -> GapCard? {
        let s = l.weekendSplit(end: reportWeekEnd(today: t))
        guard s.enough else { return nil }
        return GapCard(answer: s.passes ? Copy.groupName(s.low) : Copy.t(.f2flat), weekday: s.a, weekend: s.b)
    }

    /// M5 的方向換成白話。回來的週先不看方向（W-2r）
    private func easeCard(_ l: Ledger, today t: DayKey) -> EaseCard? {
        guard !l.isReturnWeek(end: currentWeekEnd(today: t)) else { return nil }
        let answer: String
        switch lineShape {
        case .few: return nil
        case .up: answer = Copy.t(.f3up)
        case .down: answer = Copy.t(.f3down)
        case .mixed: answer = Copy.t(.f3mixed)
        case .flat: answer = Copy.t(signals(today: t).flatLow ? .f3low : .f3flat)
        }
        return EaseCard(answer: answer, weekly: Array(weekly.suffix(8)))
    }

    /// M18：看得出來才出
    private func timeCard(today t: DayKey) -> TimeCard? {
        usualTime(today: t).map { TimeCard(answer: Copy.t(.f5a, ["time": $0.text]), time: $0) }
    }

    /// 最近 84 天有寫理由的跳過，次數多的在前，一樣多的取比較近的
    private func skipCard(_ l: Ledger, today t: DayKey) -> SkipCard? {
        let from = t.adding(-(Threshold.skipWindow - 1))
        var counts: [String: (n: Int, last: DayKey)] = [:]
        for r in l.byDay.values.sorted(by: { $0.day < $1.day }) where r.kind == .leave && r.day >= from && r.day <= t {
            let reason = (r.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !reason.isEmpty { counts[reason] = ((counts[reason]?.n ?? 0) + 1, r.day) }
        }
        let list = counts.sorted { ($0.value.n, $0.value.last) > ($1.value.n, $1.value.last) }
        let total = list.reduce(0) { $0 + $1.value.n }
        guard let top = list.first, total >= Threshold.skipMin else { return nil }
        let items = list.map { Copy.t(.f4item, ["reason": $0.key, "k": $0.value.n]) }
        return SkipCard(answer: top.key, list: items.joined(separator: "、"))
    }

    /// 三張裡最早看得到的那一張
    private func fewCard(_ l: Ledger, today t: DayKey) -> FewCard {
        let dates: [(DayKey?, CopyID)] = [(weekDate(l, today: t), .fewWeek),
                                          (gapDate(l, today: t), .fewGap),
                                          (easeDate(l, today: t), .fewEase)]
        var first: (day: DayKey, what: CopyID)? = nil
        for (date, what) in dates {
            guard let date else { continue }
            if let f = first, f.day <= date { continue }
            first = (day: date, what: what)
        }
        guard let soon = first else { return FewCard(title: Copy.t(.fewSoon), progress: nil) }
        let title = Copy.t(.fewOn, ["date": "\(soon.day.month)月\(soon.day.day)日", "what": Copy.t(soon.what)])
        let all = DayKey.days(from: l.planted, to: soon.day)
        let gone = DayKey.days(from: l.planted, to: t)
        return FewCard(title: title, progress: all > 0 ? min(1, max(0, Double(gone) / Double(all))) : nil)
    }

    // 推日期：照常記下去，哪一天過門檻（最早是明天）。放手測試中不推

    /// M4 湊滿完整週之後，下一週的第一天
    private func weekDate(_ l: Ledger, today t: DayKey) -> DayKey? {
        guard letgo == nil else { return nil }
        let e0 = currentWeekEnd(today: t)
        for k in 1...8 {
            let e = e0.adding(7 * k)
            var n = 0
            for i in 1...Threshold.usualWeeks {
                let w = l.week(end: e.adding(-7 * i))
                if !w.partial, w.letgo == 0, !w.touchesPause, w.hasRecord || w.end >= e0 { n += 1 }
            }
            if n >= Threshold.usualMin { return e.adding(-6) }
        }
        return nil
    }

    /// M7 兩組都夠天數的那個週回顧日
    private func gapDate(_ l: Ledger, today t: DayKey) -> DayKey? {
        guard letgo == nil else { return nil }
        let e0 = reportWeekEnd(today: t)
        for k in 1...12 {
            let e = e0.adding(7 * k)
            let start = max(l.planted, e.adding(-(Threshold.weekendWindow - 1)))
            guard e >= start, DayKey.days(from: start, to: e) + 1 >= Threshold.spanDays else { continue }
            var weekday = 0
            var weekend = 0
            var d = start
            while d <= e {
                let ahead = d >= t && !l.hasRecord(d)
                if ahead || (l.isComparable(d) && !l.isTravel(d)) {
                    if d.weekday == 0 || d.weekday == 6 { weekend += 1 } else { weekday += 1 }
                }
                d = d.adding(1)
            }
            if weekday >= Threshold.groupDays && weekend >= Threshold.groupDays { return e }
        }
        return nil
    }

    /// 第 3 次開始四問：種滿 7 天後，每個回顧週問一次。次數夠了還沒出，是回來的週，等下一週
    private func easeDate(_ l: Ledger, today t: DayKey) -> DayKey? {
        guard letgo == nil else { return nil }
        if weekly.count >= 3 { return currentWeekEnd(today: t).adding(1) }
        var count = weekly.count
        var last = weekly.last?.date
        var d = max(t.adding(1), l.planted.adding(7))
        for _ in 0..<60 {
            let due = last.map { DayKey.days(from: $0, to: lastReviewDay(today: d)) >= 6 } ?? true
            if due {
                count += 1
                last = d
                if count >= 3 { return d }
            }
            d = d.adding(1)
        }
        return nil
    }
}
