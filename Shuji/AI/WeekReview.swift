import Foundation

// 任務 9 週報：四問答完，AI 看一週的天數，說一句發現、給一個改法（多米 2026-11-25 定）。
// 數字與「有沒有規律」全部由程式算好再送，AI 不自己數。沒接 AI、失敗、太久：用程式寫的那一句。

// MARK: 一週七片葉

struct WeekLeaf: Equatable {
    enum Kind: Equatable {
        /// 放手日、種下之前、今天還沒記、換時區跳過的那天：什麼都不畫
        case none
        case done
        /// 做了，而且是回來的那一節（開花）
        case back
        case skip
        case missed
    }

    var day: DayKey
    var kind: Kind

    var grown: Bool { kind == .done || kind == .back }
}

extension Ledger {
    /// 結束在 e 的那一週，照日子排的七天
    func weekLeaves(end e: DayKey) -> [WeekLeaf] {
        (0..<7).map { i in
            let d = e.adding(i - 6)
            return WeekLeaf(day: d, kind: leafKind(d))
        }
    }

    private func leafKind(_ d: DayKey) -> WeekLeaf.Kind {
        if d < planted || d > today || isLetGo(d) { return .none }
        if isDone(d) { return isReturn(d) ? .back : .done }
        if isLeave(d) { return .skip }
        return isMissed(d) ? .missed : .none
    }

    /// 那一週是種下去的第幾週
    func weekNumber(end e: DayKey) -> Int { max(0, DayKey.days(from: planted, to: e)) / 7 + 1 }
}

// MARK: 輸入

/// 欄位名跟伺服器一字不差
struct WeekReviewInput: Codable, Equatable {
    struct Skip: Codable, Equatable {
        /// 例：星期六
        var day: String
        var reason: String
    }

    struct Week: Codable, Equatable {
        var done: Int
        /// 做了加漏了。跳過、放手的日子不算
        var possible: Int
        var missed: [String]
        var skipped: [Skip]
    }

    struct Reason: Codable, Equatable {
        var reason: String
        var count: Int
    }

    var floor: String
    var trigger: String
    var days_planted: Int
    var week: Week
    /// 最近 6 週
    var weekday: GroupCount
    var weekend: GroupCount
    /// weekend、weekday（比較少的那一組）、none。過了門檻才不是 none
    var pattern: String
    /// 最近 84 天跳過的理由，次數多的在前
    var reasons: [Reason]
}

extension AppState {
    func weekReviewInput(end e: DayKey, today t: DayKey) -> WeekReviewInput? {
        guard let h = habit else { return nil }
        let l = ledger(today: t)
        let leaves = l.weekLeaves(end: e)
        let done = leaves.filter(\.grown).count
        let missed = leaves.filter { $0.kind == .missed }.map { "星期\($0.day.weekName)" }
        let skipped = leaves.filter { $0.kind == .skip }.map {
            WeekReviewInput.Skip(day: "星期\($0.day.weekName)", reason: l.skipReason($0.day))
        }
        let split = l.weekendSplit(end: e)
        return WeekReviewInput(floor: String(h.floor.prefix(40)), trigger: String(h.trigger.prefix(40)),
                               days_planted: max(0, DayKey.days(from: h.planted, to: t)) + 1,
                               week: .init(done: done, possible: done + missed.count, missed: missed, skipped: skipped),
                               weekday: split.a, weekend: split.b,
                               pattern: weekPattern(l, split: split, end: e),
                               reasons: l.topSkipReasons())
    }

    /// 跟「這週的田」的平日／週末觀察同一道門檻（M7、C9）：種下那週、放手的週、回來的週不講規律
    private func weekPattern(_ l: Ledger, split: Split, end e: DayKey) -> String {
        let w = l.week(end: e)
        guard split.passes, !w.partial, !w.allLetGo, !l.isReturnWeek(end: e) else { return "none" }
        return split.low
    }
}

private extension Ledger {
    func skipReason(_ d: DayKey) -> String {
        String((record(d)?.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
    }

    /// 最近 84 天，最多五個；一樣多的取比較近的
    func topSkipReasons() -> [WeekReviewInput.Reason] {
        let from = today.adding(-(Threshold.skipWindow - 1))
        var counts: [String: (n: Int, last: DayKey)] = [:]
        for r in byDay.values.sorted(by: { $0.day < $1.day }) where r.kind == .leave && r.day >= from && r.day <= today {
            let reason = skipReason(r.day)
            if !reason.isEmpty { counts[reason] = ((counts[reason]?.n ?? 0) + 1, r.day) }
        }
        return counts.sorted { ($0.value.n, $0.value.last) > ($1.value.n, $1.value.last) }
            .prefix(5)
            .map { WeekReviewInput.Reason(reason: $0.key, count: $0.value.n) }
    }
}

extension DayKey {
    /// 一、二…日
    var weekName: String { DayKey.weekNames[weekday] }
}

// MARK: 輸出

struct WeekReviewOutput: Decodable, Equatable {
    struct Change: Decodable, Equatable {
        /// trigger、floor、backup
        var field: String
        var label: String
        var text: String
    }

    /// ok 或 unfit
    var type: String
    var finding: String
    var change: Change?
}

/// 檢查過、可以直接寫進去的改法
struct WeekChange: Equatable {
    var field: HabitField
    var label: String
    var text: String

    /// 欄位不認得、沒有字、跟現在一樣：當作沒有改法
    init?(_ c: WeekReviewOutput.Change?, habit: Habit) {
        guard let c else { return nil }
        var text = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // AI 給的是一個瞬間（吃完早午餐）；「不順的時候」那一格要看得懂整句
        if c.field == "backup", !text.isEmpty, !text.contains("就") { text += "就\(habit.floor)" }
        text = String(text.prefix(60))
        let label = c.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let now: String
        switch c.field {
        case "trigger":
            field = .trigger
            now = habit.trigger
        case "floor":
            field = .floor
            now = habit.floor
        case "backup":
            field = .backup
            now = habit.backup
        default:
            return nil
        }
        guard text != now else { return nil }
        self.text = text
        self.label = label.isEmpty ? field.label : label
    }
}

// MARK: 程式寫的那一句

enum WeekWords {
    /// 沒有 AI 的時候泡泡裡說什麼
    static func fallback(_ i: WeekReviewInput) -> String {
        [main(i), skips(i)].filter { !$0.isEmpty }.joined()
    }

    /// AI 那句沒有句號就補上
    static func sentence(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = s.last, !"。！？…".contains(last) else { return s }
        return s + "。"
    }

    private static func main(_ i: WeekReviewInput) -> String {
        let missed = i.week.missed
        if i.week.possible == 0 { return i.week.skipped.isEmpty ? "這週不用記。" : "這週都跳過。" }
        if missed.isEmpty { return "這週一天沒漏。" }
        // 規律過了門檻，而且這週真的全部漏在那一邊，才講「都」
        let weekend: Set<String> = ["星期六", "星期日"]
        if i.pattern == "weekend", missed.allSatisfy({ weekend.contains($0) }) { return "漏的都在週末。" }
        if i.pattern == "weekday", missed.allSatisfy({ !weekend.contains($0) }) { return "漏的都在平日。" }
        return "這週漏了 \(missed.count) 天。"
    }

    private static func skips(_ i: WeekReviewInput) -> String {
        var list: [String] = []
        for s in i.week.skipped where !s.reason.isEmpty && !list.contains(s.reason) { list.append(s.reason) }
        return list.isEmpty ? "" : "跳過是因為\(list.joined(separator: "、"))。"
    }

    /// 藤那張圖念出來的一句
    static func spoken(_ leaves: [WeekLeaf]) -> String {
        let groups: [(WeekLeaf.Kind, String)] = [(.done, "做了"), (.back, "回來"), (.skip, "跳過"), (.missed, "漏了")]
        let parts = groups.compactMap { kind, verb -> String? in
            let names = leaves.filter { $0.kind == kind }.map { $0.day.weekName }
            return names.isEmpty ? nil : "星期\(names.joined(separator: "、"))\(verb)"
        }
        return parts.isEmpty ? "這週沒有葉子。" : parts.joined(separator: "，") + "。"
    }
}

// MARK: 呼叫

@MainActor
enum WeekReviewAI {
    /// 最多等 20 秒；失敗、不適合、太久都回 nil
    static func ask(_ input: WeekReviewInput, habitId: String?) async -> WeekReviewOutput? {
        await withTaskGroup(of: WeekReviewOutput?.self) { group in
            group.addTask { await WeekReviewAI.send(input, habitId: habitId) }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func send(_ input: WeekReviewInput, habitId: String?) async -> WeekReviewOutput? {
        guard let out = try? await AIClient.shared.run(.weekReview, input: input, habitId: habitId,
                                                       as: WeekReviewOutput.self) else { return nil }
        guard case .result(let o) = out, o.type == "ok",
              !o.finding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return o
    }
}
