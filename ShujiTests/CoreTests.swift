import XCTest
@testable import Shuji

// 標準答案是用 Node 跑原型 index.html 裡同一段 JS 算出來的（today 固定 2026-11-07），
// 這裡只比對 Swift 版算出來的是不是一模一樣。

private let T = DayKey("2026-11-07")!

/// 原型「載入示範資料」後「匯出備份」會得到的那段 JSON，一字不改
private let prototypeBackup = """
{"v":1,"habit":{"floor":"打開檔案寫一句","trigger":"起床喝完第一杯水","travelFloor":"在手機上寫三行","obstacle":"如果早上要出門，就在捷運上用手機寫三行","backup":"如果中午前還沒打開過檔案，就在第一餐吃完時打開","why":"把複雜的事想清楚、寫下來","planted":"2026-09-23"},"logs":{"2026-09-23":{"t":"done"},"2026-09-24":{"t":"done"},"2026-09-25":{"t":"done"},"2026-09-26":{"t":"done"},"2026-09-27":{"t":"done"},"2026-09-30":{"t":"done"},"2026-10-01":{"t":"done"},"2026-10-02":{"t":"done"},"2026-10-03":{"t":"done"},"2026-10-04":{"t":"done"},"2026-10-05":{"t":"done"},"2026-10-07":{"t":"done"},"2026-10-08":{"t":"done"},"2026-10-09":{"t":"done"},"2026-10-10":{"t":"leave","reason":"出遠門"},"2026-10-11":{"t":"done"},"2026-10-12":{"t":"done"},"2026-10-13":{"t":"done"},"2026-10-16":{"t":"done"},"2026-10-17":{"t":"done"},"2026-10-18":{"t":"done"},"2026-10-19":{"t":"done"},"2026-10-20":{"t":"done"},"2026-10-21":{"t":"done"},"2026-10-22":{"t":"done"},"2026-10-24":{"t":"done"},"2026-10-25":{"t":"done"},"2026-10-26":{"t":"done"},"2026-10-27":{"t":"done"},"2026-10-28":{"t":"done"},"2026-10-29":{"t":"done"},"2026-10-30":{"t":"done"},"2026-11-01":{"t":"done"},"2026-11-02":{"t":"done"},"2026-11-03":{"t":"done"},"2026-11-04":{"t":"done"},"2026-11-05":{"t":"done"},"2026-11-06":{"t":"done"}},"weekly":[{"date":"2026-09-29","scores":[2.25,2.25,2.25,2.25],"avg":2.25},{"date":"2026-10-06","scores":[3,3,3,3],"avg":3},{"date":"2026-10-13","scores":[3.75,3.75,3.75,3.75],"avg":3.75},{"date":"2026-10-20","scores":[4.25,4.25,4.25,4.25],"avg":4.25},{"date":"2026-10-27","scores":[4.75,4.75,4.75,4.75],"avg":4.75},{"date":"2026-11-03","scores":[5,5,5,5],"avg":5},{"date":"2026-11-10","scores":[5,5,5,5],"avg":5}],"basket":[{"floor":"刷完牙做一下伸展","trigger":"刷完牙","nodes":71,"ret":9,"days":84,"planted":"2026-06-25","dug":"2026-09-17"}],"queue":["坐上蒲團按計時器","換上球鞋拿球出門"],"pressure":null,"letgo":null,"letgoResult":null,"justDug":null,"travelEndedOn":null,"settings":{"sound":true,"reviewDay":0,"leave":2},"dayOffset":0}
"""

private func localDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
    return Calendar.current.date(from: c)!
}

// MARK: - 日期

final class DayKeyTests: XCTestCase {
    func testParseAndFormat() {
        XCTAssertEqual(DayKey("2026-11-07")?.string, "2026-11-07")
        XCTAssertEqual(DayKey("2026-01-05")?.string, "2026-01-05")
        XCTAssertNil(DayKey("2026-13-01"))
        XCTAssertNil(DayKey("abc"))
        XCTAssertNil(DayKey("2026-11"))
    }

    func testDayNumberMatchesPrototypeDayNo() {
        XCTAssertEqual(DayKey("1970-01-01")!.dayNumber, 0)
        XCTAssertEqual(DayKey("2000-02-29")!.dayNumber, 11016)
        XCTAssertEqual(DayKey("2026-11-07")!.dayNumber, 20764)
    }

    func testWeekdayMatchesJSGetDay() {
        XCTAssertEqual(DayKey("2026-11-07")!.weekday, 6)
        XCTAssertEqual(DayKey("2026-01-01")!.weekday, 4)
        XCTAssertEqual(DayKey("2000-01-01")!.weekday, 6)
        XCTAssertEqual(DayKey("1970-01-01")!.weekday, 4)
    }

    func testAddingAcrossBoundaries() {
        XCTAssertEqual(DayKey("2024-02-28")!.adding(1).string, "2024-02-29")
        XCTAssertEqual(DayKey("2025-12-31")!.adding(1).string, "2026-01-01")
        XCTAssertEqual(DayKey("2026-03-01")!.adding(-1).string, "2026-02-28")
        XCTAssertEqual(DayKey("2026-11-07")!.adding(-45).string, "2026-09-23")
    }

    func testDaysBetween() {
        XCTAssertEqual(DayKey.days(from: DayKey("2026-09-23")!, to: T), 45)
        XCTAssertEqual(DayKey.days(from: T, to: DayKey("2026-09-23")!), -45)
    }

    func testRoundTripOverWideRange() {
        for n in stride(from: -200_000, through: 200_000, by: 997) {
            XCTAssertEqual(DayKey(dayNumber: n).dayNumber, n)
        }
    }

    func testComparableFollowsCalendar() {
        XCTAssertTrue(DayKey("2026-09-30")! < DayKey("2026-10-01")!)
        XCTAssertTrue(DayKey("2025-12-31")! < DayKey("2026-01-01")!)
    }

    func testFourAMBoundary() {
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 3, 59)).string, "2026-11-06")
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 4, 0)).string, "2026-11-07")
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 23, 30)).string, "2026-11-07")
    }

    func testOffset() {
        XCTAssertEqual(DayKey.today(now: localDate(2026, 11, 7, 12, 0), offset: 7).string, "2026-11-14")
    }

    func testDisplay() {
        XCTAssertEqual(T.long, "11月7日 星期六")
        XCTAssertEqual(T.short, "11/7")
        XCTAssertEqual(T.monthPrefix, "2026-11")
    }
}

// MARK: - 計算

final class LogicTests: XCTestCase {
    private var demo: AppState { AppState.demo(today: T) }

    func testDemoStatsMatchPrototype() {
        let s = demo.stats(today: T)
        XCTAssertEqual(s, AppState.Stats(nodes: 37, ret: 5, missed: 7, leaves: 0, leaveLeft: 2))
    }

    func testReturnsMatchPrototype() {
        let d = demo
        let ds = d.doneKeys
        let returns = ds.filter { d.isReturn($0, doneKeys: ds) }.map(\.string)
        XCTAssertEqual(returns, ["2026-09-30", "2026-10-07", "2026-10-16", "2026-10-24", "2026-11-01"])
        // 請假隔天不算回來（請假有紀錄）
        XCTAssertFalse(d.isReturn(DayKey("2026-10-11")!))
        // 第一節不算回來
        XCTAssertFalse(d.isReturn(DayKey("2026-09-23")!))
    }

    func testLastDoneAndConsecutiveMissed() {
        var d = demo
        XCTAssertEqual(d.lastDone?.string, "2026-11-06")
        XCTAssertEqual(d.consecutiveMissed(today: T), 0)
        d.logs["2026-11-06"] = nil
        d.logs["2026-11-05"] = nil
        XCTAssertEqual(d.consecutiveMissed(today: T), 2)
        XCTAssertEqual(d.lastDone?.string, "2026-11-04")
    }

    func testNeedReview() {
        for rd in 0..<7 {
            var d = demo
            d.settings.reviewDay = rd
            XCTAssertFalse(d.needReview(today: T), "示範資料最後一次四問在未來，任何回顧日都不該再問")
        }
        var d = demo
        d.settings.reviewDay = 6
        d.weekly = []
        XCTAssertTrue(d.needReview(today: T))
        d.weekly = [WeeklyReview(date: T.adding(-6), scores: [4, 4, 4, 4])]
        XCTAssertTrue(d.needReview(today: T))
        d.weekly = [WeeklyReview(date: T.adding(-5), scores: [4, 4, 4, 4])]
        XCTAssertFalse(d.needReview(today: T))
        d.settings.reviewDay = 5
        d.weekly = []
        XCTAssertFalse(d.needReview(today: T), "今天星期六，回顧日是星期五")
    }

    func testReviewPendingStaysThreeDays() {
        var d = demo
        d.settings.reviewDay = 6   // 2026-11-07 是星期六
        d.weekly = []
        XCTAssertEqual(d.lastReviewDay(today: T), T)
        XCTAssertTrue(d.reviewPending(today: T))
        XCTAssertTrue(d.reviewPending(today: T.adding(1)))
        XCTAssertTrue(d.reviewPending(today: T.adding(3)))
        XCTAssertFalse(d.reviewPending(today: T.adding(4)), "回顧日過了三天就不留了")
        XCTAssertEqual(d.lastReviewDay(today: T.adding(4)), T)
        XCTAssertEqual(d.lastReviewDay(today: T.adding(7)), T.adding(7))

        d.weekly = [WeeklyReview(date: T.adding(-6), scores: [4, 4, 4, 4])]
        XCTAssertTrue(d.reviewPending(today: T), "回顧日當天的判斷跟 needReview 相同")
        XCTAssertEqual(d.reviewPending(today: T), d.needReview(today: T))
        d.weekly = [WeeklyReview(date: T.adding(-5), scores: [4, 4, 4, 4])]
        XCTAssertFalse(d.reviewPending(today: T))
        XCTAssertEqual(d.reviewPending(today: T), d.needReview(today: T))

        d.weekly = [WeeklyReview(date: T.adding(1), scores: [4, 4, 4, 4])]
        XCTAssertFalse(d.reviewPending(today: T.adding(2)), "回顧日隔天做了，之後就不再提")

        d.habit = nil
        XCTAssertFalse(d.reviewPending(today: T))
    }

    func testObstacleMigratesIntoBackup() {
        var d = demo
        d.habit?.backup = ""
        d.habit?.obstacle = "如果早上要出門，就在捷運上用手機寫三行"
        d.migrateFields()
        XCTAssertEqual(d.habit?.backup, "如果早上要出門，就在捷運上用手機寫三行")
        XCTAssertEqual(d.habit?.obstacle, "如果早上要出門，就在捷運上用手機寫三行", "obstacle 留著，原型還讀得到")

        var e = demo
        e.habit?.backup = "已經有備案"
        e.habit?.obstacle = "舊的障礙版"
        e.migrateFields()
        XCTAssertEqual(e.habit?.backup, "已經有備案", "backup 有值就不蓋")
    }

    func testSignals() {
        let sg = demo.signals()
        XCTAssertEqual(sg, AppState.Signals(s1: true, flatLow: false, s2: false, s3: false, n: 7))
        XCTAssertEqual(sg.passCount, 1)

        var d = demo
        d.pressure = true
        XCTAssertEqual(d.signals().passCount, 2)

        d.weekly = (0..<6).map { WeeklyReview(date: T.adding(-42 + $0 * 7), scores: [2, 2, 2, 2]) }
        let low = d.signals()
        XCTAssertTrue(low.s1)
        XCTAssertTrue(low.flatLow)

        d.weekly = (0..<5).map { WeeklyReview(date: T.adding(-35 + $0 * 7), scores: [5, 5, 5, 5]) }
        XCTAssertFalse(d.signals().s1, "不到六週不算走平")
    }

    func testLetGoPriorAndRule() {
        XCTAssertEqual(demo.doneInLast14Days(today: T), 13)
    }

    func testMissedExcludesFinishedLetGoWindow() {
        var d = demo
        d.logs["2026-11-01"] = nil
        d.logs["2026-11-02"] = nil
        XCTAssertEqual(d.stats(today: T).missed, 9)
        d.letgoResult = LetGoResult(days: 12, prior: 13, pass: true, start: DayKey("2026-11-01")!, end: DayKey("2026-11-07")!)
        XCTAssertEqual(d.stats(today: T).missed, 7, "放手那幾天不算漏掉")
        d.letgoResult = LetGoResult(days: 12, prior: 13, pass: true, start: DayKey("2026-10-31")!, end: DayKey("2026-11-07")!)
        XCTAssertEqual(d.stats(today: T).missed, 6, "10/31 本來就漏掉，被放手窗口蓋住也不算")
    }

    func testLongAbsence() {
        var d = demo
        d.logs = ["2026-10-01": .done]
        XCTAssertTrue(d.longAbsence(today: T))
        d.letgoResult = LetGoResult(days: 10, prior: 10, pass: true, start: DayKey("2026-10-20")!, end: DayKey("2026-11-03")!)
        XCTAssertFalse(d.longAbsence(today: T), "放手測試剛結束，不算停了一陣子")
        d.logs[T.string] = .done
        XCTAssertFalse(d.longAbsence(today: T))
        d.logs = [:]
        XCTAssertFalse(d.longAbsence(today: T), "一節都沒有的時候不算停")
    }

    func testActiveFloor() {
        var d = demo
        XCTAssertEqual(d.activeFloor, "打開檔案寫一句")
        d.travel = true
        XCTAssertEqual(d.activeFloor, "在手機上寫三行")
        d.habit?.travelFloor = ""
        XCTAssertEqual(d.activeFloor, "打開檔案寫一句")
    }

    func testPhrasesAreStablePerDay() {
        XCTAssertEqual(Phrases.phrase(for: T, isReturn: false), Phrases.done[18])
        XCTAssertEqual(Phrases.phrase(for: T, isReturn: true), Phrases.returns[4])
        XCTAssertEqual(Phrases.done.count, 22)
        XCTAssertEqual(Phrases.returns.count, 10)
    }

    func testWordingRules() {
        XCTAssertTrue(Wording.isNegative("不滑手機"))
        XCTAssertTrue(Wording.isNegative("少吃甜食"))
        XCTAssertTrue(Wording.isNegative("戒菸"))
        XCTAssertTrue(Wording.isNegative("避免熬夜"))
        XCTAssertFalse(Wording.isNegative("打開檔案寫一句"))
        XCTAssertFalse(Wording.isNegative("讀一頁書"))
        XCTAssertTrue(Wording.isFood("減重五公斤"))
        XCTAssertTrue(Wording.isFood("記錄熱量"))
        XCTAssertFalse(Wording.isFood("坐上蒲團按計時器"))
    }
}

// MARK: - JSON 跟原型互通

final class CodableTests: XCTestCase {
    func testDecodesPrototypeBackup() throws {
        let s = try JSONDecoder().decode(AppState.self, from: Data(prototypeBackup.utf8))
        XCTAssertEqual(s.habit?.floor, "打開檔案寫一句")
        XCTAssertEqual(s.habit?.planted.string, "2026-09-23")
        XCTAssertEqual(s.logs.count, 38)
        XCTAssertEqual(s.logs["2026-10-10"]?.t, .leave)
        XCTAssertEqual(s.logs["2026-10-10"]?.reason, "出遠門")
        XCTAssertEqual(s.weekly.count, 7)
        XCTAssertEqual(s.weekly[0].avg, 2.25)
        XCTAssertEqual(s.basket.count, 1)
        XCTAssertEqual(s.basket[0].nodes, 71)
        XCTAssertEqual(s.queue, ["坐上蒲團按計時器", "換上球鞋拿球出門"])
        XCTAssertNil(s.pressure)
        XCTAssertNil(s.letgo)
        XCTAssertNil(s.letgoResult)
        XCTAssertEqual(s.settings.leave, 2)
        XCTAssertEqual(s.settings.reviewDay, 0)
        XCTAssertTrue(s.settings.sound)
        XCTAssertFalse(s.settings.check)
        XCTAssertEqual(s.dayOffset, 0)
        XCTAssertFalse(s.travel)
        XCTAssertEqual(s.stats(today: T), AppState.Stats(nodes: 37, ret: 5, missed: 7, leaves: 0, leaveLeft: 2))
    }

    func testPrototypeBackupEqualsBuiltInDemo() throws {
        let s = try JSONDecoder().decode(AppState.self, from: Data(prototypeBackup.utf8))
        XCTAssertEqual(s, AppState.demo(today: T))
    }

    func testRoundTrip() throws {
        let a = try JSONDecoder().decode(AppState.self, from: Data(prototypeBackup.utf8))
        let data = try JSONEncoder().encode(a)
        let b = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(a, b)
    }

    func testEncodedShapeLooksLikePrototype() throws {
        let data = try JSONEncoder().encode(AppState.demo(today: T))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["v", "habit", "logs", "weekly", "basket", "queue", "settings", "dayOffset"] {
            XCTAssertNotNil(obj[key], "缺 \(key)")
        }
        let logs = try XCTUnwrap(obj["logs"] as? [String: [String: Any]])
        XCTAssertEqual(logs["2026-09-23"]?["t"] as? String, "done")
        XCTAssertEqual(logs["2026-10-10"]?["reason"] as? String, "出遠門")
        let habit = try XCTUnwrap(obj["habit"] as? [String: Any])
        XCTAssertEqual(habit["planted"] as? String, "2026-09-23")
    }

    func testToleratesMissingKeysAndNulls() throws {
        let s = try JSONDecoder().decode(AppState.self, from: Data("{\"logs\":{}}".utf8))
        XCTAssertNil(s.habit)
        XCTAssertEqual(s.settings.leave, 2)
        let t = try JSONDecoder().decode(AppState.self, from: Data(
            "{\"v\":1,\"habit\":null,\"logs\":{\"2026-11-01\":{\"t\":\"done\"},\"bad\":{\"t\":\"done\"}},\"pressure\":null,\"travel\":true}".utf8))
        XCTAssertNil(t.pressure)
        XCTAssertEqual(t.logs.count, 1, "不合法的日期 key 要丟掉")
        XCTAssertTrue(t.travel)
    }
}

// MARK: - 動作

@MainActor
final class StoreTests: XCTestCase {
    private func makeStore(backupDir: URL? = nil) -> Store {
        Store(now: { localDate(2026, 11, 7, 12, 0) }, fileURL: nil, backupDir: backupDir)
    }

    func testDigWritesBackupFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shuji-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = makeStore(backupDir: dir)
        s.state = AppState.demo(today: T)
        s.dig()
        let url = dir.appendingPathComponent("薯記備份-挖地瓜-2026-11-07.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let saved = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.logs.count, 38, "備份是挖之前的狀態")
        XCTAssertEqual(saved.habit?.floor, "打開檔案寫一句")
        XCTAssertTrue(s.state.logs.isEmpty, "挖完才歸零")
    }

    func testImportMigratesObstacle() {
        let s = makeStore()
        let json = "{\"habit\":{\"floor\":\"讀一頁書\",\"trigger\":\"刷完牙\",\"obstacle\":\"出門的話在車上讀\",\"planted\":\"2026-11-01\"},\"logs\":{}}"
        XCTAssertTrue(s.importJSON(json))
        XCTAssertEqual(s.state.habit?.backup, "出門的話在車上讀")
    }

    func testTodayAndOffset() {
        let s = makeStore()
        XCTAssertEqual(s.today, T)
        s.advance(days: 1)
        XCTAssertEqual(s.today, T.adding(1))
        s.resetOffset()
        XCTAssertEqual(s.today, T)
    }

    func testPlantThenLog() {
        let s = makeStore()
        s.addQueue("讀一頁書")
        s.plant(floor: "讀一頁書", trigger: "刷完牙")
        XCTAssertEqual(s.state.habit?.planted, T)
        XCTAssertEqual(s.state.queue, [], "種下去的那個要從排隊裡拿掉")
        XCTAssertFalse(s.logToday(), "第一節不是回來")
        XCTAssertEqual(s.state.log(on: T)?.t, .done)
        XCTAssertTrue(s.vineGrow)
        let before = s.state
        s.logToday()
        XCTAssertEqual(s.state, before, "同一天記兩次不會變")
    }

    func testReturnFlower() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.state.logs["2026-11-06"] = nil
        XCTAssertTrue(s.logToday(), "昨天沒紀錄，今天這一節是回來")
    }

    func testBackfillYesterday() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.state.logs["2026-11-06"] = nil
        XCTAssertTrue(s.canBackfillYesterday)
        s.backfillYesterday()
        XCTAssertEqual(s.state.log(on: T.adding(-1))?.t, .done)
        XCTAssertFalse(s.canBackfillYesterday)
        XCTAssertFalse(s.vineGrow)
    }

    func testLeaveLimitAndUndo() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.leaveToday(reason: "發燒")
        XCTAssertEqual(s.state.log(on: T)?.t, .leave)
        XCTAssertEqual(s.lastLeaveReason, "發燒")
        s.undoToday()
        XCTAssertNil(s.state.log(on: T))
        s.updateSettings { $0.leave = 0 }
        s.leaveToday(reason: "發燒")
        XCTAssertNil(s.state.log(on: T), "本月沒有請假額度就不能請")
    }

    func testLetGoFlow() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.startLetGo()
        XCTAssertEqual(s.state.letgo?.prior, 13)
        XCTAssertEqual(s.state.letgoDaysLeft(today: T), 14)
        XCTAssertFalse(s.showLetGoEnd)
        s.endLetGoEarly()
        XCTAssertTrue(s.showLetGoEnd)
        s.finishLetGo(days: 11)
        XCTAssertNil(s.state.letgo)
        XCTAssertEqual(s.state.letgoResult?.pass, true, "11 >= 13 - 2 算過")
        XCTAssertEqual(s.state.letgoResult?.start, T)
        XCTAssertEqual(s.state.letgoResult?.end, T)
        XCTAssertEqual(s.page, 0)
        XCTAssertTrue(s.state.signals().s3)

        let f = makeStore()
        f.state = AppState.demo(today: T)
        f.startLetGo()
        f.endLetGoEarly()
        f.finishLetGo(days: 10)
        XCTAssertEqual(f.state.letgoResult?.pass, false, "10 < 11 不算過")
    }

    func testDigAndPlantNext() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.dig()
        XCTAssertEqual(s.state.basket.count, 2)
        XCTAssertEqual(s.state.basket[0].nodes, 37)
        XCTAssertEqual(s.state.basket[0].ret, 5)
        XCTAssertEqual(s.state.basket[0].days, 46)
        XCTAssertEqual(s.state.basket[0].dug, T)
        XCTAssertNotNil(s.state.justDug)
        XCTAssertTrue(s.state.logs.isEmpty)
        XCTAssertTrue(s.state.weekly.isEmpty)
        XCTAssertNotNil(s.state.habit, "挖完還沒按「種下一個」之前習慣還在")
        s.plantNext()
        XCTAssertNil(s.state.habit)
        XCTAssertNil(s.state.justDug)
    }

    func testReviewAndPressure() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.recordReview(scores: [5, 6, 7, 6])
        XCTAssertEqual(s.state.weekly.count, 8)
        XCTAssertEqual(s.state.weekly.last?.avg, 6)
        XCTAssertEqual(s.state.weekly.last?.date, T)
        s.setPressure(true)
        XCTAssertEqual(s.state.pressure, true)
    }

    func testImportRequiresLogs() {
        let s = makeStore()
        XCTAssertFalse(s.importJSON("{\"habit\":null}"))
        XCTAssertFalse(s.importJSON("not json"))
        XCTAssertTrue(s.importJSON(prototypeBackup))
        XCTAssertEqual(s.state.habit?.floor, "打開檔案寫一句")
        XCTAssertEqual(s.exportJSON().isEmpty, false)
    }

    func testTravelEndRemembersDay() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.setTravel(true)
        XCTAssertTrue(s.state.travel)
        s.setTravel(false)
        XCTAssertEqual(s.state.travelEndedOn, T)
    }

    func testWipe() {
        let s = makeStore()
        s.state = AppState.demo(today: T)
        s.wipe()
        XCTAssertEqual(s.state, AppState())
    }
}
