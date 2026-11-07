import Foundation

extension AppState {
    /// 原型「載入示範資料」：種了 45 天，漏 7 天、請假 1 天、七週開始四問、排隊兩個、竹籃一顆。
    static func demo(today t: DayKey, settings: Settings = Settings(), dayOffset: Int = 0) -> AppState {
        var s = AppState()
        s.settings = settings
        s.dayOffset = dayOffset
        let start = t.adding(-45)
        s.habit = Habit(
            floor: "打開檔案寫一句",
            trigger: "起床喝完第一杯水",
            planted: start,
            travelFloor: "在手機上寫三行",
            obstacle: "如果早上要出門，就在捷運上用手機寫三行",
            backup: "如果中午前還沒打開過檔案，就在第一餐吃完時打開",
            why: "把複雜的事想清楚、寫下來"
        )
        let skip: Set<Int> = [5, 6, 13, 21, 22, 30, 38]
        for i in 0..<45 {
            let k = start.adding(i)
            if i == 17 {
                s.logs[k.string] = .leave("出遠門")
            } else if !skip.contains(i) {
                s.logs[k.string] = .done
            }
        }
        let av: [Double] = [2.25, 3, 3.75, 4.25, 4.75, 5, 5]
        for (i, a) in av.enumerated() {
            s.weekly.append(WeeklyReview(date: start.adding(6 + i * 7), scores: [a, a, a, a]))
        }
        s.queue = ["坐上蒲團按計時器", "換上球鞋拿球出門"]
        s.basket = [Potato(floor: "刷完牙做一下伸展", trigger: "刷完牙", nodes: 71, ret: 9, days: 84,
                           planted: start.adding(-90), dug: start.adding(-6))]
        return s
    }
}
