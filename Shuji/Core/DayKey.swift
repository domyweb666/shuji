import Foundation

/// 一天的鍵，字串形式是 "YYYY-MM-DD"，跟原型存在 localStorage 裡的 key 一樣。
/// 凌晨四點換日：`today(now:)` 先把現在時間往前推四小時，再取本地日期。
struct DayKey: Hashable, Comparable, Codable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(_ string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    init(dayNumber: Int) {
        let (y, m, d) = DayKey.civil(fromDays: dayNumber)
        self.init(year: y, month: m, day: d)
    }

    var string: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { string }
    /// "YYYY-MM"，算本月請假用
    var monthPrefix: String { String(format: "%04d-%02d", year, month) }

    /// 1970-01-01 起算的天數，同原型的 dayNo
    var dayNumber: Int { DayKey.days(fromCivil: year, month, day) }
    /// 0 是星期日，同 JS 的 getDay
    var weekday: Int { ((dayNumber % 7) + 7 + 4) % 7 }

    func adding(_ n: Int) -> DayKey { DayKey(dayNumber: dayNumber + n) }
    static func days(from a: DayKey, to b: DayKey) -> Int { b.dayNumber - a.dayNumber }
    static func < (l: DayKey, r: DayKey) -> Bool { l.dayNumber < r.dayNumber }

    /// 現在算哪一天。offset 是測試區「往後 N 天」用的。
    static func today(now: Date = Date(), offset: Int = 0, calendar: Calendar = .current) -> DayKey {
        let shifted = now.addingTimeInterval(-4 * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return DayKey(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1).adding(offset)
    }

    /// 這一天在本地時區的某個時刻
    func date(hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return calendar.date(from: c)
    }

    // MARK: Codable（存成字串）

    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DayKey(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "讀不出日期：\(s)"))
        }
        self = k
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }

    // MARK: 顯示

    static let weekNames = ["日", "一", "二", "三", "四", "五", "六"]
    /// 「11月7日 星期六」
    var long: String { "\(month)月\(day)日 星期\(DayKey.weekNames[weekday])" }
    /// 「11/7」
    var short: String { "\(month)/\(day)" }

    // MARK: 曆法（Howard Hinnant 的 days_from_civil / civil_from_days，整數運算，不碰時區）

    static func days(fromCivil y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civil(fromDays z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}
