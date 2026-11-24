import XCTest
@testable import Shuji

/// 田 → 分析的四張問句卡。2026-11-22 是星期日（預設回顧日），那週是 11/16 到 11/22
private let T = DayKey("2026-11-22")!

private struct Plot {
    var s = AppState()

    init(planted: DayKey) {
        s.habit = Habit(floor: "打開檔案寫一句", trigger: "起床喝完第一杯水", planted: planted, id: "hab")
        s.settings.reviewDay = 0
    }

    mutating func done(_ d: DayKey) { add(.done, d, nil) }
    mutating func leave(_ d: DayKey, _ reason: String) { add(.leave, d, reason) }

    private mutating func add(_ kind: LogKind, _ d: DayKey, _ reason: String?) {
        s.records.append(DayRecord(id: "rec-\(s.records.count)", habit: "hab", kind: kind, day: d,
                                   at: nil, tz: "Asia/Taipei", source: .hold, reason: reason))
    }

    /// 從種下那天到 last，照 rule 決定記不記
    mutating func fill(to last: DayKey, _ rule: (DayKey) -> Bool = { _ in true }) {
        var d = s.habit!.planted
        while d <= last {
            if rule(d) { done(d) }
            d = d.adding(1)
        }
    }

    /// 最近幾次開始四問，最後一次在 T，一週一次
    mutating func reviews(_ values: [Double]) {
        s.reviews = values.enumerated().map { i, v in
            WeeklyReview(date: T.adding(-7 * (values.count - 1 - i)), scores: [v, v, v, v], id: "rev-\(i)", habit: "hab")
        }
    }

    var cards: FieldCards { s.fieldCards(today: T) }
}

private func isWeekend(_ d: DayKey) -> Bool { d.weekday == 0 || d.weekday == 6 }

final class FieldReportTests: XCTestCase {
    /// 8 週前的星期一種下，一到昨天都記
    private func everyDay() -> Plot {
        var p = Plot(planted: T.adding(-55))
        p.fill(to: T.adding(-1))
        return p
    }

    // MARK: 這週做得多嗎

    func testWeekCard() {
        var p = Plot(planted: T.adding(-55))
        // 平日才記，上上週五漏一天
        p.fill(to: T) { !isWeekend($0) && $0 != T.adding(-9) }
        let w = p.cards.week
        XCTAssertEqual(w?.answer, "5 天，平常 4 到 5 天")
        XCTAssertEqual(w?.rows.map(\.done), [5, 5, 5, 5, 5, 5, 4, 5])
        XCTAssertEqual(w?.from, "八週前")
        XCTAssertNil(p.cards.few)
    }

    func testWeekCardSameAndEmpty() {
        var p = everyDay()
        XCTAssertEqual(p.cards.week?.answer, "6 天，平常 7 天", "今天還沒記")
        p.done(T)
        XCTAssertEqual(p.s.fieldCards(today: T.adding(1)).week?.answer, "還沒記，平常 7 天", "新的一週第一天不寫 0")
    }

    func testWeekCardShortHistory() {
        var p = Plot(planted: T.adding(-20))
        p.fill(to: T)
        XCTAssertEqual(p.cards.week?.rows.count, 3)
        XCTAssertEqual(p.cards.week?.from, "三週前")
    }

    // MARK: 哪幾天常漏掉

    func testGapCard() {
        var p = Plot(planted: T.adding(-55))
        p.fill(to: T) { !isWeekend($0) }
        let g = p.cards.gap
        XCTAssertEqual(g?.answer, "週末")
        XCTAssertEqual(g?.weekday, GroupCount(done: 30, days: 30))
        XCTAssertEqual(g?.weekend, GroupCount(done: 0, days: 11), "今天還沒記不算進去")

        var q = Plot(planted: T.adding(-55))
        q.fill(to: T) { isWeekend($0) || $0.weekday == 1 || $0.weekday == 3 }
        XCTAssertEqual(q.cards.gap?.answer, "平日")

        XCTAssertEqual(everyDay().cards.gap?.answer, "看不出差別")
    }

    func testGapCardNeedsDays() {
        var p = Plot(planted: T.adding(-27))
        p.fill(to: T)
        XCTAssertNil(p.cards.gap, "四週只有 8 個週末日")
    }

    // MARK: 不用想就會做了嗎

    func testEaseCard() {
        var p = everyDay()
        p.reviews([3, 4])
        XCTAssertNil(p.cards.ease, "不到 3 次不出")
        let cases: [([Double], String)] = [
            ([3, 4, 5], "越來越不用想"),
            ([5, 5, 5], "差不多"),
            ([5, 4, 3], "最近比較要逼自己"),
            ([3, 5, 4], "每次不太一樣"),
            ([2, 2, 2, 2, 2, 2], "還要逼自己"),
        ]
        for (values, answer) in cases {
            p.reviews(values)
            XCTAssertEqual(p.cards.ease?.answer, answer, "\(values)")
        }
        p.reviews(Array(repeating: 4, count: 12))
        XCTAssertEqual(p.cards.ease?.weekly.count, 8)
    }

    // MARK: 跳過都因為什麼

    func testSkipCard() {
        var p = Plot(planted: T.adding(-100))
        p.leave(T.adding(-90), "生病")
        p.leave(T.adding(-30), "旅行")
        p.leave(T.adding(-20), "太累")
        p.leave(T.adding(-10), "")
        XCTAssertNil(p.cards.skips, "有理由的不到 3 次；84 天以前的、沒理由的不算")
        p.leave(T.adding(-9), "旅行 ")
        XCTAssertEqual(p.cards.skips, SkipCard(answer: "旅行", list: "旅行 2 次、太累 1 次"))
        p.leave(T.adding(-8), "太累")
        XCTAssertEqual(p.cards.skips?.answer, "太累", "一樣多取比較近的")
    }

    // MARK: 都還不夠

    func testFewCard() {
        var p = Plot(planted: T.adding(-2))
        p.fill(to: T.adding(-1))
        let c = p.cards
        XCTAssertNil(c.week)
        XCTAssertNil(c.gap)
        XCTAssertNil(c.ease)
        XCTAssertEqual(c.few?.title, "12月7日看得到這週做得多不多", "11/23、11/30 兩個完整週之後")
        XCTAssertEqual(c.few?.progress ?? 0, 2.0 / 17, accuracy: 0.001)

        // 那天真的看得到
        let day = DayKey("2026-12-07")!
        p.s.records = []
        p.fill(to: day.adding(-1))
        XCTAssertNil(p.s.fieldCards(today: day.adding(-1)).week)
        XCTAssertNotNil(p.s.fieldCards(today: day).week)
    }

    func testFewCardPicksReviewWhenSooner() {
        var p = Plot(planted: T.adding(-8))
        p.fill(to: T.adding(-1))
        p.reviews([3, 4])
        XCTAssertEqual(p.cards.few?.title, "11月29日看得到是不是不用想就會做", "下一個回顧日是第 3 次")
    }

    func testFewCardWithoutDate() {
        var p = Plot(planted: T.adding(-2))
        p.s.marks.append(Mark(id: "m", habit: "hab", kind: .letgoStart, day: T.adding(-1), at: nil, tz: nil))
        XCTAssertEqual(p.cards.few, FewCard(title: "再記幾天就看得到", progress: nil))
    }

    /// 停了 20 天今天回來：這週不比較、也不看方向，下一週再出
    func testReturnWeek() {
        var p = Plot(planted: T.adding(-60))
        p.fill(to: T) { $0 <= T.adding(-21) || $0 == T }
        p.reviews([5, 5, 5])
        let c = p.cards
        XCTAssertNil(c.week)
        XCTAssertNil(c.ease)
        XCTAssertEqual(c.few?.title, "11月23日看得到是不是不用想就會做")
        XCTAssertNotNil(p.s.fieldCards(today: T.adding(1)).ease)
    }
}
