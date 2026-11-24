import XCTest
@testable import Shuji

/// 2026-11-22 是星期日（預設回顧日），那一週是 11/16 星期一到 11/22 星期日
private let T = DayKey("2026-11-22")!

final class WeekReviewTests: XCTestCase {
    private let hid = "hab-test"

    private func state(planted: DayKey) -> AppState {
        var s = AppState()
        s.habit = Habit(floor: "坐上蒲團", trigger: "刷完牙", planted: planted, id: hid)
        return s
    }

    private func add(_ s: inout AppState, _ d: DayKey, _ kind: LogKind = .done, reason: String? = nil) {
        s.records.append(DayRecord(id: "rec-\(s.records.count)", habit: hid, kind: kind, day: d,
                                   at: nil, tz: "Asia/Taipei", source: .hold, reason: reason))
    }

    private func fill(_ s: inout AppState, to last: DayKey, _ rule: (DayKey) -> Bool) {
        var d = s.habit!.planted
        while d <= last {
            if rule(d) { add(&s, d) }
            d = d.adding(1)
        }
    }

    private func isWeekend(_ d: DayKey) -> Bool { d.weekday == 0 || d.weekday == 6 }

    /// 種了六週多，週末一天都沒做；明天看，所以星期日也算漏
    private func weekendGap() -> AppState {
        var s = state(planted: T.adding(-48))
        fill(&s, to: T) { !isWeekend($0) }
        return s
    }

    private func input(_ s: AppState, today: DayKey = T.adding(1)) -> WeekReviewInput {
        s.weekReviewInput(end: T, today: today)!
    }

    // MARK: 七片葉

    func testLeavesOfAPlainWeek() {
        let leaves = weekendGap().ledger(today: T.adding(1)).weekLeaves(end: T)
        XCTAssertEqual(leaves.map(\.day.weekName), ["一", "二", "三", "四", "五", "六", "日"])
        XCTAssertEqual(leaves.map(\.kind), [.back, .done, .done, .done, .done, .missed, .missed])
        XCTAssertEqual(WeekWords.spoken(leaves), "星期二、三、四、五做了，星期一回來，星期六、日漏了。")
    }

    func testTodayNotLoggedIsNotMissed() {
        let s = weekendGap()
        let leaves = s.ledger(today: T).weekLeaves(end: T)
        XCTAssertEqual(leaves.last?.kind, WeekLeaf.Kind.none, "今天還沒過完")
        XCTAssertEqual(input(s, today: T).week, .init(done: 5, possible: 6, missed: ["星期六"], skipped: []))
    }

    func testSkipAndLetGoAreNotPossibleDays() {
        var s = state(planted: T.adding(-30))
        // 11/19、11/20 放手，11/18 跳過，其他都做
        let off: Set<DayKey> = [T.adding(-4), T.adding(-3), T.adding(-2)]
        fill(&s, to: T) { !off.contains($0) }
        add(&s, T.adding(-4), .leave, reason: " 旅行 ")
        s.marks = [Mark(id: "m1", habit: hid, kind: .letgoStart, day: T.adding(-3), at: nil, tz: nil, prior: 10),
                   Mark(id: "m2", habit: hid, kind: .letgoEnd, day: T.adding(-1), at: nil, tz: nil, prior: 10, recalled: 2, pass: true)]
        let i = input(s)
        XCTAssertEqual(i.week, .init(done: 4, possible: 4, missed: [], skipped: [.init(day: "星期三", reason: "旅行")]))
        XCTAssertEqual(i.reasons, [.init(reason: "旅行", count: 1)])
        XCTAssertEqual(WeekWords.fallback(i), "這週一天沒漏。跳過是因為旅行。")
        let leaves = s.ledger(today: T.adding(1)).weekLeaves(end: T)
        XCTAssertEqual(leaves.map(\.kind), [.done, .done, .skip, .none, .none, .done, .done], "放手日不畫，放手完那天不算回來")
    }

    func testBeforePlantingIsBlank() {
        var s = state(planted: T.adding(-2))
        fill(&s, to: T) { _ in true }
        XCTAssertEqual(s.ledger(today: T).weekLeaves(end: T).map(\.kind), [.none, .none, .none, .none, .done, .done, .done])
        XCTAssertEqual(input(s, today: T).days_planted, 3)
    }

    func testWeekNumber() {
        XCTAssertEqual(state(planted: T.adding(-20)).ledger(today: T).weekNumber(end: T), 3, "第 21 天是第 3 週")
        XCTAssertEqual(state(planted: T.adding(-21)).ledger(today: T).weekNumber(end: T), 4)
    }

    // MARK: 規律

    func testPatternNeedsTheThreshold() {
        let i = input(weekendGap())
        XCTAssertEqual(i.pattern, "weekend")
        XCTAssertEqual(i.weekend.done, 0)
        XCTAssertEqual(WeekWords.fallback(i), "漏的都在週末。")

        // 同樣漏週末，才種三週：週末不到 10 天，不講規律
        var few = state(planted: T.adding(-20))
        fill(&few, to: T) { !isWeekend($0) }
        XCTAssertEqual(input(few).pattern, "none")
        XCTAssertEqual(WeekWords.fallback(input(few)), "這週漏了 2 天。")
    }

    func testWeekdayPattern() {
        var s = state(planted: T.adding(-48))
        fill(&s, to: T) { isWeekend($0) || $0.weekday == 1 }
        XCTAssertEqual(input(s).pattern, "weekday")
        XCTAssertEqual(WeekWords.fallback(input(s)), "漏的都在平日。")
    }

    func testPatternWordsOnlyWhenThisWeekMatches() {
        // 六週下來週末比較少，但這週漏的有一天是星期三
        var s = state(planted: T.adding(-48))
        fill(&s, to: T) { !isWeekend($0) && $0 != T.adding(-4) }
        let i = input(s)
        XCTAssertEqual(i.pattern, "weekend")
        XCTAssertEqual(WeekWords.fallback(i), "這週漏了 3 天。")
    }

    func testFirstWeekAndReturnWeekHaveNoPattern() {
        var back = state(planted: T.adding(-60))
        // 停了 10 天，星期三回來
        fill(&back, to: T) { d in !isWeekend(d) && !(d >= T.adding(-14) && d < T.adding(-4)) }
        XCTAssertTrue(back.ledger(today: T).isReturnWeek(end: T))
        XCTAssertEqual(input(back).pattern, "none")
    }

    // MARK: 備用句

    private func week(_ done: Int, _ missed: [String], _ skipped: [WeekReviewInput.Skip] = [], pattern: String = "none") -> WeekReviewInput {
        WeekReviewInput(floor: "a", trigger: "b", days_planted: 30,
                        week: .init(done: done, possible: done + missed.count, missed: missed, skipped: skipped),
                        weekday: .zero, weekend: .zero, pattern: pattern, reasons: [])
    }

    func testFallbackLines() {
        XCTAssertEqual(WeekWords.fallback(week(7, [])), "這週一天沒漏。")
        XCTAssertEqual(WeekWords.fallback(week(7, [], pattern: "weekend")), "這週一天沒漏。")
        XCTAssertEqual(WeekWords.fallback(week(5, ["星期二", "星期日"])), "這週漏了 2 天。")
        XCTAssertEqual(WeekWords.fallback(week(5, ["星期六", "星期日"])), "這週漏了 2 天。", "沒過門檻不講規律")
        XCTAssertEqual(WeekWords.fallback(week(6, [], [.init(day: "星期三", reason: "")])), "這週一天沒漏。")
        let two: [WeekReviewInput.Skip] = [.init(day: "星期三", reason: "旅行"), .init(day: "星期四", reason: "旅行"),
                                           .init(day: "星期五", reason: "生病")]
        XCTAssertEqual(WeekWords.fallback(week(3, ["星期一"], two)), "這週漏了 1 天。跳過是因為旅行、生病。")
        XCTAssertEqual(WeekWords.fallback(week(0, [], two)), "這週都跳過。跳過是因為旅行、生病。")
        XCTAssertEqual(WeekWords.fallback(week(0, [])), "這週不用記。")
    }

    func testFallbackHasNoForbiddenWords() {
        let lines = [week(7, []), week(5, ["星期一", "星期日"]), week(5, ["星期六", "星期日"], pattern: "weekend"),
                     week(5, ["星期一"], pattern: "weekday"), week(0, [])].map { WeekWords.fallback($0) }
        for line in lines {
            for w in Copy.forbidden { XCTAssertFalse(line.contains(w), "「\(line)」有禁用詞「\(w)」") }
        }
    }

    // MARK: 輸出

    func testOutputDecodes() throws {
        let json = "{\"type\":\"ok\",\"finding\":\"漏的多半在六日。\",\"change\":{\"field\":\"backup\",\"label\":\"下週六日改成\",\"text\":\"吃完早午餐\"},\"category\":null,\"message\":null}"
        let o = try JSONDecoder().decode(WeekReviewOutput.self, from: Data(json.utf8))
        XCTAssertEqual(o.change?.field, "backup")
        let none = try JSONDecoder().decode(WeekReviewOutput.self, from: Data("{\"type\":\"ok\",\"finding\":\"這週七天都做了。\",\"change\":null}".utf8))
        XCTAssertNil(none.change)
    }

    func testChangeIsCheckedBeforeItCanBeApplied() {
        let h = Habit(floor: "坐上蒲團", trigger: "刷完牙", planted: T)
        func make(_ field: String, _ text: String) -> WeekChange? {
            WeekChange(WeekReviewOutput.Change(field: field, label: "下週六日改成", text: text), habit: h)
        }
        XCTAssertEqual(make("backup", " 起床就坐上去 ")?.text, "起床就坐上去")
        XCTAssertEqual(make("backup", "吃完早午餐")?.text, "吃完早午餐就坐上蒲團", "只給瞬間就補成整句")
        XCTAssertEqual(make("trigger", "吃完早餐")?.field, .trigger)
        XCTAssertNil(make("trigger", "刷完牙"), "跟現在一樣")
        XCTAssertNil(make("floor", "  "))
        XCTAssertNil(make("why", "為了健康"), "這一格不給改")
        XCTAssertNil(WeekChange(nil, habit: h))
    }

    func testFindingEndsWithAFullStop() {
        XCTAssertEqual(WeekWords.sentence("這週週末兩天都漏了 "), "這週週末兩天都漏了。")
        XCTAssertEqual(WeekWords.sentence("漏的都在週末。"), "漏的都在週末。")
        XCTAssertEqual(WeekWords.sentence(""), "")
    }

    @MainActor
    func testApplyingAChangeIsRecordedFromTheWeek() {
        let s = Store(fileURL: nil, backupDir: nil)
        s.plant(floor: "坐上蒲團", trigger: "刷完牙")
        let c = WeekChange(WeekReviewOutput.Change(field: "backup", label: "x", text: "起床就坐上去"), habit: s.state.habit!)!
        s.updateHabit(via: .week) { c.field.apply(c.text, to: &$0) }
        XCTAssertEqual(s.state.habit?.backup, "起床就坐上去")
        XCTAssertEqual(s.state.changes.last?.via, .week)
        XCTAssertEqual(s.state.changes.last?.field, .backup)
    }
}
