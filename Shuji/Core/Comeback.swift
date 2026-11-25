import Foundation

// 回來與放手（docs/回來與放手-規格.md，2026-11-25）：漏掉那段的理由、提醒怎麼退場、竹籃每週問一句。
// 全部是純函式，today 由外面傳進來。

// MARK: - 資料

/// 一段漏掉的日子和他選的理由。那幾天照樣算漏掉，每天的紀錄不動。
struct Gap: Codable, Equatable, Identifiable {
    var id: String
    var habit: String
    var from: DayKey
    /// 含這天
    var to: DayKey
    /// 空字串：不說、或把卡收掉
    var reason: String
    var at: String?
    var tz: String?

    func covers(_ d: DayKey) -> Bool { d >= from && d <= to }
}

/// 竹籃裡的地瓜，每週問一句還會做嗎
struct BasketCheck: Codable, Equatable, Identifiable {
    var id: String
    var potato: String
    var day: DayKey
    var still: Bool
    var at: String?
    var tz: String?
}

/// 還沒問過的那一段（含頭尾）
struct PendingGap: Equatable {
    var from: DayKey
    var to: DayKey

    var days: Int { DayKey.days(from: from, to: to) + 1 }
    /// 只有昨天：先問有沒有做
    var onlyYesterday: Bool { from == to }
}

/// 提醒走到哪一段
enum ReminderStage: Equatable {
    case daily, afterMiss, off
}

/// ⚪ 起點數字，照真的使用再改
enum ComebackRule {
    /// 漏到這麼多天就是「停了一陣子」，今天頁自己會說
    static let longDays = 14
    /// 種滿幾天提醒才會開始退
    static let reminderMinDays = 28
    /// 看最近幾天漏幾次、每一段至少待幾天
    static let reminderWindow = 14
    static let reminderMaxMissed = 1
    /// 開始四問平均要到量表中間
    static let easeMin = 4.0
    /// 挖出來幾天之後才問、每顆隔幾天
    static let basketFirst = 14
    static let basketEvery = 7
}

// MARK: - 漏掉的那一段

extension AppState {
    var habitGaps: [Gap] {
        guard let id = habitID else { return [] }
        return gaps.filter { $0.habit == id }
    }

    /// 從昨天往前連續漏掉、還沒問過的那一段。停了一陣子不算。
    func pendingGap(today t: DayKey) -> PendingGap? {
        guard habit != nil, justDug == nil, letgo == nil else { return nil }
        let l = ledger(today: t)
        let asked = habitGaps
        var run = 0
        var from: DayKey? = nil
        var to: DayKey? = nil
        var open = true
        var k = t.adding(-1)
        while k >= l.planted {
            if l.isTimezoneSkip(k) {
                k = k.adding(-1)
                continue
            }
            guard l.isMissed(k) else { break }
            run += 1
            if asked.contains(where: { $0.covers(k) }) { open = false }
            if open {
                from = k
                if to == nil { to = k }
            }
            k = k.adding(-1)
        }
        guard run < ComebackRule.longDays, let first = from, let last = to else { return nil }
        return PendingGap(from: first, to: last)
    }

    /// 停了一陣子之後，今天接上了
    func returnedFromLong(today t: DayKey) -> Bool {
        guard log(on: t)?.t == .done, doneKeys.contains(where: { $0 < t }) else { return false }
        return consecutiveMissed(today: t) >= ComebackRule.longDays
    }

    /// 最近 84 天漏掉的理由，最多五個；一樣多的取比較近的。只算那段裡真的還有漏掉的日子
    func topGapReasons(today t: DayKey) -> [WeekReviewInput.Reason] {
        let since = t.adding(-(Threshold.skipWindow - 1))
        let l = ledger(today: t)
        var counts: [String: (n: Int, last: DayKey)] = [:]
        for g in habitGaps.sorted(by: { $0.to < $1.to }) where g.to >= since && g.to < t {
            let reason = String(g.reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
            guard !reason.isEmpty, g.hasMissed(l) else { continue }
            counts[reason] = ((counts[reason]?.n ?? 0) + 1, g.to)
        }
        return counts.sorted { ($0.value.n, $0.value.last) > ($1.value.n, $1.value.last) }
            .prefix(5)
            .map { WeekReviewInput.Reason(reason: $0.key, count: $0.value.n) }
    }
}

private extension Gap {
    func hasMissed(_ l: Ledger) -> Bool {
        var d = from
        while d <= to {
            if l.isMissed(d) { return true }
            d = d.adding(1)
        }
        return false
    }
}

// MARK: - 提醒退場

extension AppState {
    private var lastReminderMark: Mark? {
        habitMarks.last(where: { $0.kind.isReminder })
    }

    var reminderStage: ReminderStage {
        guard let m = lastReminderMark else { return .daily }
        switch m.kind {
        case .remindAfterMiss: return .afterMiss
        case .remindOff: return .off
        default: return .daily
        }
    }

    /// 最近 14 天漏了幾天
    private func recentMissed(today t: DayKey) -> Int {
        let l = ledger(today: t)
        return (1...ComebackRule.reminderWindow).filter { l.isMissed(t.adding(-$0)) }.count
    }

    /// 很少漏、開始也不太用想了
    private func reminderCalm(today t: DayKey) -> Bool {
        guard let h = habit, DayKey.days(from: h.planted, to: t) >= ComebackRule.reminderMinDays,
              let last = weekly.last, last.avg >= ComebackRule.easeMin,
              DayKey.days(from: last.date, to: t) <= ComebackRule.reminderWindow,
              lineShape == .up || lineShape == .flat else { return false }
        return recentMissed(today: t) <= ComebackRule.reminderMaxMissed
    }

    /// 現在該換到哪一段；不用換是 nil。要關掉得先問，不在這裡
    func reminderShift(today t: DayKey) -> Mark.Kind? {
        guard settings.check, habit != nil, letgo == nil, justDug == nil else { return nil }
        switch reminderStage {
        case .daily:
            // 剛調回每天的、自己剛打開的，先待滿兩週
            if let m = lastReminderMark, DayKey.days(from: m.day, to: t) < ComebackRule.reminderWindow { return nil }
            return reminderCalm(today: t) ? .remindAfterMiss : nil
        case .afterMiss:
            return consecutiveMissed(today: t) >= 2 ? .remindDaily : nil
        case .off:
            return nil
        }
    }

    /// 可以跟他說不用提醒了
    func reminderCanStop(today t: DayKey) -> Bool {
        guard settings.check, reminderStage == .afterMiss, let m = lastReminderMark,
              DayKey.days(from: m.day, to: t) >= ComebackRule.reminderWindow else { return false }
        return recentMissed(today: t) <= ComebackRule.reminderMaxMissed
    }

    /// 提醒退場之後又連漏：要不要開回來
    func reminderMayReturn(today t: DayKey) -> Bool {
        guard !settings.check, reminderStage == .off, let off = lastReminderMark?.day else { return false }
        let l = ledger(today: t)
        return (2...4).contains { n in
            let d = t.adding(-n)
            return d >= off && l.isMissed(d) && l.isMissed(d.adding(1))
        }
    }

    /// 接下來哪幾天該響（由早到晚）。只在漏掉後提醒的話，前一天漏了那天才響
    func reminderDays(today t: DayKey) -> [DayKey] {
        guard checkShouldSchedule(today: t) else { return [] }
        let open = log(on: t) == nil
        var out: [DayKey] = []
        if reminderStage == .daily {
            if open { out.append(t) }
            out.append(t.adding(1))
        } else {
            if open && ledger(today: t).isMissed(t.adding(-1)) { out.append(t) }
            if open { out.append(t.adding(1)) }
            out.append(t.adding(2))
        }
        return out
    }

    /// 通知那一句：跟著時機走
    var reminderText: String {
        guard let h = habit else { return "" }
        return "\(h.trigger)，\(activeFloor)。做完回來按住一下。"
    }
}

extension Mark.Kind {
    var isReminder: Bool { self == .remindDaily || self == .remindAfterMiss || self == .remindOff }
}

// MARK: - 竹籃

extension Potato {
    /// 舊資料可能沒有編號
    var key: String { id.isEmpty ? "\(planted.string)-\(dug.string)" : id }
}

extension AppState {
    /// 最近兩次都說有點掉了
    func faded(_ p: Potato) -> Bool {
        let last = Array(checks.filter { $0.potato == p.key }.suffix(2))
        return last.count == 2 && !last[0].still && !last[1].still
    }

    /// 這週要問的那一顆：最久沒問的。這個回顧週問過就不問
    func basketAsk(today t: DayKey) -> Potato? {
        guard let h = habit, reviewedThisWeek(today: t) else { return nil }
        if let last = checks.map(\.day).max(), last >= lastReviewDay(today: t) { return nil }
        func lastDay(_ p: Potato) -> DayKey {
            checks.filter { $0.potato == p.key }.map(\.day).max() ?? p.dug
        }
        let ready = basket.filter { p in
            guard DayKey.days(from: p.dug, to: t) >= ComebackRule.basketFirst,
                  DayKey.days(from: lastDay(p), to: t) >= ComebackRule.basketEvery else { return false }
            return !faded(p) && p.floor != h.floor && !queue.contains(p.floor)
        }
        return ready.min { lastDay($0) < lastDay($1) }
    }
}
