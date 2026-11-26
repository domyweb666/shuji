import XCTest
@testable import Shuji

/// 同時養好幾個（多米 2026-11-26：今天頁切換選單）
@MainActor
final class MultiHabitTests: XCTestCase {
    private func makeStore() -> Store {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 26; c.hour = 12
        let now = Calendar.current.date(from: c)!
        return Store(now: { now }, fileURL: nil, backupDir: nil)
    }

    private func add(_ s: Store, _ floor: String, name: String = "") {
        s.addingHabit = true
        s.plant(floor: floor, trigger: "刷完牙", name: name)
    }

    func testAddingKeepsCurrentAndSwitchesToNew() {
        let s = makeStore()
        s.plant(floor: "坐上蒲團", trigger: "洗完臉", name: "冥想")
        add(s, "換上球鞋", name: "健身")
        XCTAssertEqual(s.state.habit?.name, "健身", "新的變成現在看的")
        XCTAssertEqual(s.state.others.map(\.name), ["冥想"])
        XCTAssertTrue(s.state.pastHabits.isEmpty, "一起養，不收掉")
        XCTAssertFalse(s.addingHabit, "種完就關掉")
        XCTAssertEqual(s.state.growing.count, 2)
    }

    func testPlainPlantStillReplaces() {
        let s = makeStore()
        s.plant(floor: "坐上蒲團", trigger: "洗完臉")
        s.plant(floor: "翻開書", trigger: "躺到床上")
        XCTAssertTrue(s.state.others.isEmpty)
        XCTAssertEqual(s.state.pastHabits.map(\.floor), ["坐上蒲團"])
    }

    func testSwitchKeepsRecordsPerHabit() {
        let s = makeStore()
        s.plant(floor: "坐上蒲團", trigger: "洗完臉")
        let first = s.state.habit!.id
        s.logToday()
        add(s, "換上球鞋")
        XCTAssertNil(s.state.log(on: s.today), "新的今天還沒記")
        XCTAssertTrue(s.state.didLog(first, on: s.today))
        s.switchHabit(to: first)
        XCTAssertEqual(s.state.habit?.id, first)
        XCTAssertEqual(s.state.log(on: s.today)?.t, .done)
        XCTAssertEqual(s.state.others.map(\.floor), ["換上球鞋"])
        s.switchHabit(to: "沒有這個")
        XCTAssertEqual(s.state.habit?.id, first, "找不到就不動")
    }

    func testFreeLimitIsTwo() {
        let s = makeStore()
        s.plant(floor: "a", trigger: "b")
        add(s, "c")
        XCTAssertEqual(s.maxHabits, Store.freeHabits)
        XCTAssertFalse(s.canAddHabit)
        add(s, "d")
        XCTAssertEqual(s.state.growing.count, 2, "滿了就照一般種：換掉現在的")
        XCTAssertEqual(s.state.pastHabits.map(\.floor), ["c"])
    }

    func testShelveGoesToUnfinishedAndMovesOn() {
        let s = makeStore()
        s.plant(floor: "坐上蒲團", trigger: "洗完臉")
        s.logToday()
        add(s, "換上球鞋")
        s.switchHabit(to: s.state.others[0].id)
        s.shelveHabit()
        XCTAssertEqual(s.state.habit?.floor, "換上球鞋")
        XCTAssertTrue(s.state.others.isEmpty)
        XCTAssertEqual(s.state.unfinished.map(\.habit.floor), ["坐上蒲團"])
        s.shelveHabit()
        XCTAssertNil(s.state.habit, "最後一個收起來就回到種新的")
    }

    func testOthersAreNotUnfinished() {
        let s = makeStore()
        s.plant(floor: "坐上蒲團", trigger: "洗完臉")
        s.logToday()
        add(s, "換上球鞋")
        XCTAssertTrue(s.state.unfinished.isEmpty, "還在養的不算種到一半")
    }

    func testPlantNextMovesToAnotherGrowing() {
        let s = makeStore()
        s.plant(floor: "坐上蒲團", trigger: "洗完臉")
        add(s, "換上球鞋")
        s.dig()
        s.plantNext()
        XCTAssertEqual(s.state.habit?.floor, "坐上蒲團")
        XCTAssertTrue(s.state.others.isEmpty)
    }

    func testOldSaveWithoutOthersAndRoundTrip() throws {
        let s = makeStore()
        s.plant(floor: "a", trigger: "b", name: "看書")
        add(s, "c")
        let data = try JSONEncoder().encode(s.state)
        let back = try JSONDecoder().decode(AppState.self, from: data)
        XCTAssertEqual(back.others.map(\.name), ["看書"])
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "others")
        let old = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(old.others.isEmpty)
        XCTAssertEqual(old.habit?.floor, "c")
    }
}
