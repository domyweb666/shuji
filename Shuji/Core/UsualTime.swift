import Foundation

// M18 多半什麼時候做（docs/回來與放手-規格.md）。只看按住、捷徑記的，補登和轉進來的不算。

struct UsualTime: Equatable {
    /// 每一筆從凌晨四點起算的分鐘，由小到大
    var points: [Int]
    /// 裝得下七成的那兩小時，從哪裡開始（那些點排在正中間）
    var start: Int
    /// 那段裡的中位數
    var middle: Int

    static let window = 120
    static let minCount = 10
    static let minRate = 0.7
    static let days = 28

    init?(points raw: [Int]) {
        let p = raw.sorted()
        guard p.count >= UsualTime.minCount else { return nil }
        var best: [Int] = []
        for first in p {
            let inside = p.filter { $0 >= first && $0 <= first + UsualTime.window }
            if inside.count > best.count { best = inside }
        }
        guard let first = best.first, let last = best.last, Double(best.count) / Double(p.count) >= UsualTime.minRate else { return nil }
        points = p
        start = max(0, min(1440 - UsualTime.window, (first + last - UsualTime.window) / 2))
        middle = best[best.count / 2]
    }

    /// 早上 7 點多
    var text: String {
        let hour = (middle / 60 + 4) % 24
        let name: String
        switch hour {
        case 4...5: name = "清晨"
        case 6...10: name = "早上"
        case 11...12: name = "中午"
        case 13...17: name = "下午"
        case 18...23: name = "晚上"
        default: name = "半夜"
        }
        let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(name) \(h) 點多"
    }
}

extension AppState {
    func usualTime(today t: DayKey) -> UsualTime? {
        let since = t.adding(-(UsualTime.days - 1))
        let used = activeRecords.filter { r in
            r.kind == .done && (r.source == .hold || r.source == .shortcut) && r.day >= since && r.day <= t
        }
        let points = used.compactMap { r -> Int? in
            guard let at = r.at, let date = Stamp.date(at) else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = r.tz.flatMap { TimeZone(identifier: $0) } ?? TimeZone.current
            let c = cal.dateComponents([.hour, .minute], from: date)
            return ((c.hour ?? 0) * 60 + (c.minute ?? 0) + 1200) % 1440
        }
        return UsualTime(points: points)
    }
}
