import Foundation

// 分析頁的指標（.analytics/05-指標字典.md）與這週的田（06、07、08）。
// 全部是純函式；today 由外面傳進來。數字一律在這裡算，字串表只負責填空。

/// 指標字典版本（存在每一筆觀察裡）
enum MetricVersion {
    static let current = "m2.0"
}

/// ⚪ 起點數字：照用，等 3-9 量到真值再改，改了寫進 05 改版紀錄
enum Threshold {
    /// 每組至少幾個可比較的日子
    static let groupDays = 10
    /// 窗口至少幾天
    static let spanDays = 14
    /// 兩組比例至少差多少
    static let gap = 0.30
    static let weekendWindow = 42
    static let travelWindow = 84
    static let leaveWindow = 56
    static let leaveRepeat = 2
    /// 同一種觀察幾天內不再出
    static let cooldown = 28
    static let trialDays = 14
    /// 原因連續幾次跳過或不確定，就不再問
    static let stopAsking = 3
    static let usualWeeks = 4
    static let usualMin = 2
    /// 「跳過都因為什麼」看最近幾天、有理由的至少幾次
    static let skipWindow = 84
    static let skipMin = 3
}

// MARK: - 一週

/// 一個回顧週的天數（M3）
struct WeekCount: Equatable {
    var start: DayKey
    var end: DayKey
    var done = 0
    var leave = 0
    /// 放手日
    var letgo = 0
    /// 算進來的天數（種下之後、到今天、不含放手日；今天沒紀錄不算）
    var considered = 0
    /// 今天在這週裡、還沒記
    var todayPending = false
    /// 這週有種下之前的日子
    var partial = false
    /// 這週有停頓裡的日子
    var touchesPause = false

    var hasRecord: Bool { done + leave > 0 }
    var allLetGo: Bool { letgo > 0 && considered == 0 && !todayPending }
}

/// 開始四問最近三次的方向（M5）
enum LineShape: Equatable {
    case few, flat, up, down, mixed
}

/// 兩組天數的比較（M7、M8）
struct Split: Equatable {
    var a: GroupCount
    var b: GroupCount
    /// 窗口天數
    var span: Int
    /// 窗口大約幾週
    var weeks: Int
    /// 兩組都夠天數、窗口夠長
    var enough: Bool
    /// 過門檻（夠天數而且差得夠多；旅行另外要求旅行中比較低）
    var passes: Bool
    /// 比較少的那一組：weekday、weekend、travel、home
    var low: String
    /// 天數不夠時，大約還要幾週
    var needWeeks: Int
    /// 窗口裡因為停頓沒算進來的日子
    var pausedDays: Int
}

/// 同一個請假原因（M9）
struct LeaveRepeat: Equatable {
    var total: Int
    var reason: String
    var count: Int
}

/// 試兩週到期的結果（M11）
struct TrialResult: Equatable {
    var trial: Trial
    var after: GroupCount
    /// 任一邊少於 10 天，或差不到 30 個百分點
    var smallOrClose: Bool
    /// 那兩週沒有可以比的日子
    var empty: Bool
    /// 那兩週開關句又改過
    var changedDuring: Bool
}

/// 這週的田要出的觀察（還沒存、或這週已經存過的那一筆）
struct Finding: Equatable {
    var kind: Insight.Kind
    var counts: [String: GroupCount]
    var low: String?
    var subject: String?
    var weeks: Int
    var askCause: Bool
    /// 上次選過的原因（不重問，只說一句）
    var previousCause: String?
    /// 上次的試兩週
    var previousTrial: Trial?
    /// 這週已經存過的觀察
    var recorded: Insight?
}

enum WeekObservation: Equatable {
    case trialResult(TrialResult)
    case finding(Finding)
}

/// 這週的田
struct WeekReport: Equatable {
    var start: DayKey
    var end: DayKey
    var lines: [String]
    var observation: WeekObservation?
    var isReturnWeek: Bool
}

/// 田「這幾週」的一列（M17）
struct WeekRow: Equatable {
    enum Kind: Equatable { case bar, empty, letgo, first }
    var count: WeekCount
    var kind: Kind
    var changed: Bool
    /// 種下那週：種下去第幾天
    var plantedDays: Int
}

// MARK: - 指標

extension Ledger {
    /// M3：這個回顧週（結束在 end）
    func week(end e: DayKey) -> WeekCount {
        var w = WeekCount(start: e.adding(-6), end: e)
        var d = w.start
        while d <= e {
            defer { d = d.adding(1) }
            if d < planted { w.partial = true; continue }
            if d > today { continue }
            if inPause(d) { w.touchesPause = true }
            if isLetGo(d) { w.letgo += 1; continue }
            if d == today && !hasRecord(d) { w.todayPending = true; continue }
            w.considered += 1
            if isDone(d) { w.done += 1 } else if isLeave(d) { w.leave += 1 }
        }
        return w
    }

    /// M4：前 4 個回顧週裡的完整週，最少到最多
    func usualRange(before e: DayKey) -> (lo: Int, hi: Int, weeks: Int)? {
        var values: [Int] = []
        for i in 1...Threshold.usualWeeks {
            let w = week(end: e.adding(-7 * i))
            guard !w.partial, w.letgo == 0, !w.touchesPause, w.hasRecord else { continue }
            values.append(w.done)
        }
        guard values.count >= Threshold.usualMin, let lo = values.min(), let hi = values.max() else { return nil }
        return (lo, hi, values.count)
    }

    /// 前 4 週裡有幾個完整週（不到 2 時，算還差幾週）
    func usualWeekCount(before e: DayKey) -> Int {
        var n = 0
        for i in 1...Threshold.usualWeeks {
            let w = week(end: e.adding(-7 * i))
            if !w.partial, w.letgo == 0, !w.touchesPause, w.hasRecord { n += 1 }
        }
        return n
    }

    /// C9 回來週：這週有一節，前一天剛好是一段停頓的最後一天
    func isReturnWeek(end e: DayKey) -> Bool {
        var d = e.adding(-6)
        while d <= e && d <= today {
            if isDone(d), pauses.contains(where: { $0.1 == d.dayNumber - 1 }) { return true }
            d = d.adding(1)
        }
        return false
    }

    /// M7：最近 6 週，平日／週末。a 是平日、b 是週末
    func weekendSplit(end e: DayKey) -> Split {
        let start = max(planted, e.adding(-(Threshold.weekendWindow - 1)))
        var wd = GroupCount.zero
        var we = GroupCount.zero
        var paused = 0
        var d = start
        while d <= e {
            defer { d = d.adding(1) }
            if inPause(d) { paused += 1 }
            guard isComparable(d), !isTravel(d) else { continue }
            let weekend = d.weekday == 0 || d.weekday == 6
            if weekend {
                we.days += 1
                if isDone(d) { we.done += 1 }
            } else {
                wd.days += 1
                if isDone(d) { wd.done += 1 }
            }
        }
        let span = e >= start ? DayKey.days(from: start, to: e) + 1 : 0
        let enough = wd.days >= Threshold.groupDays && we.days >= Threshold.groupDays && span >= Threshold.spanDays
        let passes = enough && abs(wd.rate - we.rate) >= Threshold.gap
        let need = max(0,
                       Int(ceil(Double(Threshold.groupDays - we.days) / 2)),
                       Int(ceil(Double(Threshold.groupDays - wd.days) / 5)),
                       Int(ceil(Double(Threshold.spanDays - span) / 7)))
        return Split(a: wd, b: we, span: span, weeks: max(1, Int((Double(span) / 7).rounded())),
                     enough: enough, passes: passes, low: we.rate < wd.rate ? "weekend" : "weekday",
                     needWeeks: need, pausedDays: paused)
    }

    /// M8：種下以來最多 84 天，旅行中／在家。a 是旅行中、b 是在家
    func travelSplit(end e: DayKey) -> Split {
        let start = max(planted, e.adding(-(Threshold.travelWindow - 1)))
        var tr = GroupCount.zero
        var home = GroupCount.zero
        var paused = 0
        var d = start
        while d <= e {
            defer { d = d.adding(1) }
            if inPause(d) { paused += 1 }
            guard isComparable(d) else { continue }
            if isTravel(d) {
                tr.days += 1
                if isDone(d) { tr.done += 1 }
            } else {
                home.days += 1
                if isDone(d) { home.done += 1 }
            }
        }
        let span = e >= start ? DayKey.days(from: start, to: e) + 1 : 0
        let enough = tr.days >= Threshold.groupDays && home.days >= Threshold.groupDays && span >= Threshold.spanDays
        let passes = enough && home.rate - tr.rate >= Threshold.gap
        return Split(a: tr, b: home, span: span, weeks: max(1, Int((Double(span) / 7).rounded())),
                     enough: enough, passes: passes, low: "travel", needWeeks: 0, pausedDays: paused)
    }

    /// 窗口裡有沒有旅行中的日子（細查層要不要出現旅行那一句）
    func hasTravel(end e: DayKey) -> Bool {
        let start = max(planted, e.adding(-(Threshold.travelWindow - 1)))
        var d = start
        while d <= e {
            if isTravel(d) { return true }
            d = d.adding(1)
        }
        return false
    }

    /// M9：最近 56 天裡請最多次的那個原因（至少 2 次）
    func leaveRepeat(end e: DayKey) -> LeaveRepeat? {
        let start = max(planted, e.adding(-(Threshold.leaveWindow - 1)))
        let leaves = byDay.values
            .filter { $0.kind == .leave && $0.day >= start && $0.day <= e }
            .sorted { $0.day < $1.day }
        var counts: [String: (n: Int, last: DayKey)] = [:]
        for r in leaves {
            let reason = (r.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else { continue }
            counts[reason] = ((counts[reason]?.n ?? 0) + 1, r.day)
        }
        guard let best = counts.max(by: { ($0.value.n, $0.value.last) < ($1.value.n, $1.value.last) }),
              best.value.n >= Threshold.leaveRepeat else { return nil }
        return LeaveRepeat(total: leaves.count, reason: best.key, count: best.value.n)
    }

    /// 這個習慣全部的請假原因，次數多的在前（細查層）
    func leaveReasons() -> [(reason: String, count: Int)] {
        var counts: [String: Int] = [:]
        for r in byDay.values where r.kind == .leave {
            let reason = (r.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            counts[reason, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }
            .sorted { ($0.count, $1.reason) > ($1.count, $0.reason) }
    }

    /// M11：試兩週那一組，在 [start, end) 裡的天數
    func trialCount(_ trial: Trial) -> GroupCount {
        var g = GroupCount.zero
        var d = trial.start
        while d < trial.end && d <= today {
            defer { d = d.adding(1) }
            guard isComparable(d), !isTravel(d) else { continue }
            let weekend = d.weekday == 0 || d.weekday == 6
            guard (trial.group == "weekend") == weekend else { continue }
            g.days += 1
            if isDone(d) { g.done += 1 }
        }
        return g
    }
}

extension AppState {
    /// M5：開始四問最近三次的方向
    var lineShape: LineShape {
        let w = weekly
        guard w.count >= 3 else { return .few }
        let l = w.suffix(3).map(\.avg)
        guard let hi = l.max(), let lo = l.min() else { return .few }
        if hi - lo <= 0.5 { return .flat }
        if l[2] == hi && l[2] - l[0] > 0.5 { return .up }
        if l[2] == lo && l[0] - l[2] > 0.5 { return .down }
        return .mixed
    }

    /// 目前習慣的觀察、試兩週
    var habitObservations: [Insight] {
        guard let id = habitID else { return [] }
        return observations.filter { $0.habit == id }
    }

    var habitTrials: [Trial] {
        guard let id = habitID else { return [] }
        return trials.filter { $0.habit == id }
    }

    /// 進行中的試兩週（最多一個）
    var runningTrial: Trial? { habitTrials.last(where: { $0.status == .running }) }

    /// M11：到期的試兩週與結果
    func dueTrial(today t: DayKey) -> TrialResult? {
        guard let trial = runningTrial, t >= trial.end else { return nil }
        return trialResult(trial, today: t)
    }

    func trialResult(_ trial: Trial, today t: DayKey) -> TrialResult {
        let l = ledger(today: t)
        let after = trial.after ?? l.trialCount(trial)
        let small = after.days < Threshold.groupDays || trial.before.days < Threshold.groupDays
            || abs(after.rate - trial.before.rate) < Threshold.gap
        let changed = changes.contains { $0.habit == trial.habit && $0.day > trial.start && $0.day < trial.end }
        return TrialResult(trial: trial, after: after, smallOrClose: small, empty: after.days == 0, changedDuring: changed)
    }

    // MARK: 這週的田

    /// 這週（今天或之前最近的回顧日結束的那一週）
    func reportWeekEnd(today t: DayKey) -> DayKey { lastReviewDay(today: t) }

    /// 這週的田要出哪一個觀察（06 挑選順序與 08 安靜規則）
    func weekObservation(today t: DayKey) -> WeekObservation? {
        guard habit != nil, letgo == nil else { return nil }
        let e = reportWeekEnd(today: t)
        let l = ledger(today: t)
        let w = l.week(end: e)
        // 回來週、整週放手、種下那週、整週沒有紀錄：都不出
        guard !w.partial, !w.allLetGo, w.hasRecord || w.todayPending, !l.isReturnWeek(end: e) else { return nil }

        if let due = dueTrial(today: t) { return .trialResult(due) }

        // 這週已經出過的，照存的那一筆（數字不會因為又記了幾天而跳動）
        if let o = habitObservations.last(where: { $0.week == e && $0.shown }) {
            return .finding(finding(from: o))
        }

        let recent = habitObservations
        func cooling(_ k: Insight.Kind) -> Bool {
            recent.contains { $0.kind == k && DayKey.days(from: $0.week, to: e) < Threshold.cooldown }
        }

        if !cooling(.leaveReason), let lv = l.leaveRepeat(end: e) {
            return .finding(Finding(kind: .leaveReason,
                                    counts: ["same": GroupCount(done: lv.count, days: lv.total)],
                                    low: nil, subject: lv.reason, weeks: 8, askCause: false,
                                    previousCause: nil, previousTrial: nil, recorded: nil))
        }
        if !cooling(.weekend), runningTrial?.kind != .weekend {
            let s = l.weekendSplit(end: e)
            if s.passes {
                return .finding(candidate(.weekend, counts: ["weekday": s.a, "weekend": s.b], low: s.low, weeks: s.weeks))
            }
        }
        if !cooling(.travel) {
            let s = l.travelSplit(end: e)
            if s.passes {
                return .finding(candidate(.travel, counts: ["travel": s.a, "home": s.b], low: "travel", weeks: s.weeks))
            }
        }
        return nil
    }

    private func candidate(_ kind: Insight.Kind, counts: [String: GroupCount], low: String, weeks: Int) -> Finding {
        let previous = habitObservations.last(where: { $0.kind == kind })
        let real = ["no_trigger", "crowded", "not_portable"]
        let previousCause = previous?.cause.flatMap { real.contains($0) ? $0 : nil }
        let previousTrial = previous?.trial.flatMap { id in habitTrials.first(where: { $0.id == id }) }
        return Finding(kind: kind, counts: counts, low: low, subject: nil, weeks: weeks,
                       askCause: previousCause == nil && !stoppedAsking,
                       previousCause: previousCause, previousTrial: previousTrial, recorded: nil)
    }

    private func finding(from o: Insight) -> Finding {
        let weeks: Int
        switch o.kind {
        case .leaveReason: weeks = 8
        case .weekend:
            let days = (o.counts["weekday"]?.days ?? 0) + (o.counts["weekend"]?.days ?? 0)
            weeks = max(1, Int((Double(days) / 7).rounded()))
        case .travel:
            let days = (o.counts["travel"]?.days ?? 0) + (o.counts["home"]?.days ?? 0)
            weeks = max(1, Int((Double(days) / 7).rounded()))
        }
        let earlier = habitObservations.last(where: { $0.kind == o.kind && $0.id != o.id && $0.week < o.week })
        let real = ["no_trigger", "crowded", "not_portable"]
        let previousCause = earlier?.cause.flatMap { real.contains($0) ? $0 : nil }
        let previousTrial = earlier?.trial.flatMap { id in habitTrials.first(where: { $0.id == id }) }
        return Finding(kind: o.kind, counts: o.counts, low: o.low, subject: o.subject, weeks: weeks,
                       askCause: o.kind != .leaveReason && previousCause == nil && o.cause == nil && !stoppedAsking,
                       previousCause: previousCause, previousTrial: previousTrial, recorded: o)
    }

    /// 原因連續 3 次都是跳過或不確定：之後只說現象（08 安靜規則 5）
    var stoppedAsking: Bool {
        let asked = habitObservations.filter { $0.kind != .leaveReason && $0.cause != nil }.suffix(Threshold.stopAsking)
        guard asked.count == Threshold.stopAsking else { return false }
        return asked.allSatisfy { $0.cause == "unanswered" || $0.cause == "not_sure" }
    }

    /// 這週的田（W-0 到 W-3＋觀察）
    func weekReport(today t: DayKey) -> WeekReport? {
        guard habit != nil else { return nil }
        let e = reportWeekEnd(today: t)
        let l = ledger(today: t)
        let isBack = l.isReturnWeek(end: e)
        return WeekReport(start: e.adding(-6), end: e,
                          lines: [lineDays(l, end: e, isBack: isBack), lineCurve(today: t, isBack: isBack), lineGrown(today: t)],
                          observation: weekObservation(today: t),
                          isReturnWeek: isBack)
    }

    /// W-1：這週記了幾天
    func lineDays(_ l: Ledger, end e: DayKey, isBack: Bool) -> String {
        let w = l.week(end: e)
        let today = w.todayPending ? Copy.t(.w1today) : ""
        let leave = w.leave > 0 ? Copy.t(.w1leave, ["m": w.leave]) : ""
        if w.allLetGo { return Copy.t(.w1letgoAll) }
        if w.partial {
            let d = DayKey.days(from: l.planted, to: min(e, l.today)) + 1
            return Copy.t(.w1first, ["d": d, "n": w.done, "today": today])
        }
        if !w.hasRecord && !w.todayPending { return Copy.t(.w1empty) }
        if w.letgo > 0 { return Copy.t(.w1letgoPart, ["n": w.done, "g": w.letgo, "today": today]) }
        if isBack { return Copy.t(.w1back, ["n": w.done, "leave": leave, "today": today]) }
        guard let u = l.usualRange(before: e) else {
            let need = max(1, Threshold.usualMin - l.usualWeekCount(before: e))
            return Copy.t(.w1noUsual, ["n": w.done, "leave": leave, "today": today, "k": need])
        }
        if u.lo == u.hi {
            return Copy.t(.w1same, ["n": w.done, "leave": leave, "today": today, "k": u.weeks, "lo": u.lo])
        }
        return Copy.t(.w1, ["n": w.done, "leave": leave, "today": today, "k": u.weeks, "lo": u.lo, "hi": u.hi])
    }

    /// W-2：開始四問的線
    func lineCurve(today t: DayKey, isBack: Bool) -> String {
        if !reviewedThisWeek(today: t) && !weekly.isEmpty { return Copy.t(.w2skipped) }
        if isBack { return Copy.t(.w2back) }
        switch lineShape {
        case .few: return Copy.t(.w2few, ["n": weekly.count])
        case .flat: return Copy.t(.w2flat)
        case .up: return Copy.t(.w2up)
        case .down: return Copy.t(.w2down)
        case .mixed: return Copy.t(.w2mixed)
        }
    }

    /// W-3：長好了嗎
    func lineGrown(today t: DayKey) -> String {
        let sg = signals(today: t)
        if sg.n < 6 { return Copy.t(.w3few, ["k": sg.passCount, "n": sg.n]) }
        if sg.grown { return Copy.t(.w3dig, ["k": sg.passCount]) }
        return Copy.t(.w3, ["k": sg.passCount])
    }

    /// 觀察的現象句（W-WE-1、W-TR-1、W-LV-1）
    func findingText(_ f: Finding) -> String {
        switch f.kind {
        case .weekend:
            let wd = f.counts["weekday"] ?? .zero
            let we = f.counts["weekend"] ?? .zero
            let args: [String: CustomStringConvertible] = ["w": f.weeks, "a": we.days, "b": we.done, "c": wd.days, "d": wd.done]
            return Copy.t(f.low == "weekday" ? .weLowWeekday : .weLowWeekend, args)
        case .travel:
            let tr = f.counts["travel"] ?? .zero
            let home = f.counts["home"] ?? .zero
            return Copy.t(.tr1, ["w": f.weeks, "a": tr.days, "b": tr.done, "c": home.days, "d": home.done])
        case .leaveReason:
            let same = f.counts["same"] ?? .zero
            return Copy.t(.lv1, ["n": same.days, "k": same.done, "reason": f.subject ?? ""])
        }
    }

    /// 試兩週結果的句子（W-EXP-1 到 4）
    func trialText(_ r: TrialResult) -> [String] {
        let g = Copy.groupName(r.trial.group)
        if r.empty {
            var lines = [Copy.t(.exp3, ["g": g])]
            if r.changedDuring { lines.append(Copy.t(.exp4)) }
            return lines
        }
        var lines = [Copy.t(.exp1, ["g": g, "a": r.after.days, "b": r.after.done, "c": r.trial.before.days, "d": r.trial.before.done])]
        if r.smallOrClose { lines.append(Copy.t(.exp2)) }
        if r.changedDuring { lines.append(Copy.t(.exp4)) }
        return lines
    }

    /// 上次的一句（W-MEM-1、W-MEM-2）
    func memoryText(_ f: Finding) -> String? {
        if let tr = f.previousTrial, let c = tr.conclusion, let label = Copy.conclusionLabel(c) {
            return Copy.t(.mem2, ["change": Copy.changeLabel(tr.change, group: tr.group), "conclusion": label])
        }
        if let c = f.previousCause, let label = Copy.causeLabel(f.kind, cause: c, low: f.low) {
            return Copy.t(.mem1, ["cause": label])
        }
        return nil
    }

    // MARK: 田的細查層

    /// M17：最近 6 個回顧週，最近的在前
    func recentWeeks(today t: DayKey, count: Int = 6) -> [WeekRow] {
        guard let h = habit else { return [] }
        let l = ledger(today: t)
        var rows: [WeekRow] = []
        var e = lastReviewDay(today: t)
        let watched: Set<HabitFieldName> = [.trigger, .floor, .backup]
        for _ in 0..<count {
            if e < h.planted { break }
            let w = l.week(end: e)
            let changed = changes.contains {
                $0.habit == h.id && watched.contains($0.field) && $0.day >= w.start && $0.day <= w.end
            }
            let kind: WeekRow.Kind
            if w.partial {
                kind = .first
            } else if w.letgo > 0 {
                kind = .letgo
            } else if !w.hasRecord && !w.todayPending {
                kind = .empty
            } else {
                kind = .bar
            }
            let plantedDays = DayKey.days(from: h.planted, to: min(e, t)) + 1
            rows.append(WeekRow(count: w, kind: kind, changed: changed, plantedDays: plantedDays))
            e = e.adding(-7)
        }
        return rows
    }
}
