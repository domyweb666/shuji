import Foundation

/// 分析頁的字串表（.analytics/07 圖表與文案）。工程照編號取字，改字只改這個檔。
/// 大括號是填空，數字一律由 Analytics 照指標字典算好再填進來。
/// 禁用詞由 AnalyticsTests 掃描：這個檔的每一句、加上 GlanceCopy 的每一句。
enum CopyID: String, CaseIterable {
    // 回顧層：這週的田
    case w0 = "W-0"
    case w0s = "W-0s"
    case w1 = "W-1"
    case w1same = "W-1="
    case w1leave = "W-1+請假"
    case w1today = "W-1t"
    case w1first = "W-1d"
    case w1empty = "W-1e"
    case w1back = "W-1r"
    case w1noUsual = "W-1n"
    case w1letgoAll = "W-1p"
    case w1letgoPart = "W-1p+"
    case w2flat = "W-2 走平"
    case w2up = "W-2 往上"
    case w2down = "W-2 往下"
    case w2mixed = "W-2 有上有下"
    case w2few = "W-2n"
    case w2back = "W-2r"
    case w2skipped = "W-2x"
    case w3 = "W-3"
    case w3dig = "W-3 可以挖"
    case w3few = "W-3n"
    case w4ok = "W-4 好"
    case w4field = "W-4 去田"

    // 回顧層：觀察
    case weLowWeekend = "W-WE-1"
    case weLowWeekday = "W-WE-1b"
    case weQ = "W-WE-Q"
    case weC1 = "W-WE-C1"
    case weC2 = "W-WE-C2"
    case c3 = "W-C3"
    case c4 = "W-C4"
    case skip = "W-SKIP"
    case aq = "W-AQ"
    case weA1 = "W-WE-A1"
    case weA2 = "W-WE-A2"
    case aTips = "W-A-TIPS"
    case aNone = "W-A-NONE"
    case tr1 = "W-TR-1"
    case trQ = "W-TR-Q"
    case trC1 = "W-TR-C1"
    case trC2 = "W-TR-C2"
    case trA2 = "W-TR-A2"
    case lv1 = "W-LV-1"
    case lvAQ = "W-LV-AQ"
    case lvA1 = "W-LV-A1"
    case lvA2 = "W-LV-A2"
    case lvA3 = "W-LV-A3"
    case noteQ = "W-NOTE-Q"
    case noteOK = "W-NOTE-OK"
    case notSure = "W-NOTSURE"
    case mem1 = "W-MEM-1"
    case mem2 = "W-MEM-2"
    case tryQ = "W-TRY-Q"
    case tryYes = "W-TRY-Y"
    case tryNo = "W-TRY-N"
    case tryOK = "W-TRY-OK"
    case done = "W-DONE"
    case exp1 = "W-EXP-1"
    case exp2 = "W-EXP-2"
    case exp3 = "W-EXP-3"
    case exp4 = "W-EXP-4"
    case expQ = "W-EXP-Q"
    case expKeep = "W-EXP-C1"
    case expSame = "W-EXP-C2"
    case expAgain = "W-EXP-C3"
    case expAgainOK = "W-EXP-AGAIN"
    case chgBackup = "做法：不順的時候"
    case chgTrigger = "做法：換開關"
    case chgTips = "做法：讓開始更容易"

    // 細查層：田
    case d1 = "D-1"
    case d1next = "D-1+"
    case d2 = "D-2"
    case d2few = "D-2n"
    case d2stale = "D-2s"
    case d2spread = "D-2w"
    case d3 = "D-3"
    case d3yes = "D-3 有"
    case d3no = "D-3 還沒"
    case d4 = "D-4"
    case d4running = "D-4 進行中"
    case d4result = "D-4 結果"
    case d4unsure = "D-4 記不清楚"
    case d5 = "D-5"
    case d5button = "D-5 按鈕"
    case d6do = "D-6 做四問"
    case d6week = "D-6 這週的田"
    case d7title = "D-7"
    case d7row = "D-7 天數"
    case d7leave = "D-7 請假"
    case d7few = "D-7n"
    case d7first = "D-7 種下那週"
    case d7empty = "D-7 沒有紀錄"
    case d7letgo = "D-7p"
    case d7changed = "D-7 改過開關"
    case d7today = "D-7 今天"
    case d7foot = "D-7 說明"
    case d8title = "D-8"
    case d8counts = "D-8 天數"
    case d8below = "D-8 未過"
    case d8over = "D-8 過"
    case d8few = "D-8n"
    case d8pause = "D-8 停下來"
    case d8travel = "D-8t"
    case d8travelFew = "D-8t n"
    case d8leaves = "D-8l"
    case d8noReason = "D-8l 沒寫"
    case d9 = "D-9"
    case d9due = "D-9 到了"
    case d9stop = "D-9 先不試了"
    case d9look = "D-9 看"

    // 田的分析：四張問句卡
    case f1q = "F-1"
    case f1a = "F-1 答案"
    case f1same = "F-1="
    case f1days = "F-1 天數"
    case f1none = "F-1e"
    case f1from = "F-1 軸"
    case f1now = "F-1 軸這週"
    case f2q = "F-2"
    case f2flat = "F-2 未過"
    case f2count = "F-2 天數"
    case f3q = "F-3"
    case f3up = "F-3 往上"
    case f3flat = "F-3 走平"
    case f3low = "F-3 走平在低處"
    case f3down = "F-3 往下"
    case f3mixed = "F-3 有上有下"
    case f3top = "F-3 上面"
    case f3bottom = "F-3 下面"
    case f4q = "F-4"
    case f4item = "F-4 一項"
    case fewOn = "F-0"
    case fewSoon = "F-0 推不出日期"
    case fewWeek = "F-0 這週"
    case fewGap = "F-0 哪幾天"
    case fewEase = "F-0 不用想"

    // 操作畫面上的一行
    case p2 = "P-2"
    case p3 = "P-3"
    case p3unsure = "P-3 記不清楚"
    case p3button = "P-3 按鈕"
    case p3disabled = "P-3 沒選"
    case p4pass = "P-4 過"
    case p4fail = "P-4 沒過"
    case p4unsure = "P-4 記不清楚"
}

enum Copy {
    static let table: [CopyID: String] = [
        .w0: "這週的田",
        .w0s: "{start} 到 {end}",
        .w1: "這週記了 {n} 天{leave}{today}。前 {k} 週是 {lo} 到 {hi} 天。",
        .w1same: "這週記了 {n} 天{leave}{today}。前 {k} 週都是 {lo} 天。",
        .w1leave: "，跳過 {m} 天",
        .w1today: "（今天還沒記）",
        .w1first: "種下去第 {d} 天，記了 {n} 天{today}。",
        .w1empty: "這週沒有紀錄。",
        .w1back: "這週接上了，記了 {n} 天{leave}{today}。",
        .w1noUsual: "這週記了 {n} 天{leave}{today}。再過 {k} 週，就有平常的範圍可以比。",
        .w1letgoAll: "放手測試中，這週不用記。",
        .w1letgoPart: "這週記了 {n} 天{today}，另外 {g} 天在放手測試。",
        .w2flat: "開始四問最近三次差不到半格，線在走平。",
        .w2up: "開始四問最近三次往上走。",
        .w2down: "開始四問最近三次往下走。",
        .w2mixed: "開始四問最近三次有上有下。",
        .w2few: "開始四問做了 {n} 次，做到第 3 次就看得出線往哪走。",
        .w2back: "開始四問的線接著畫，這次先不看方向。",
        .w2skipped: "這週沒做開始四問，線上會空一格。",
        .w3: "長好了嗎：三個訊號過了 {k} 個。",
        .w3dig: "長好了嗎：三個訊號過了 {k} 個，田裡可以挖地瓜了。",
        .w3few: "長好了嗎：三個訊號過了 {k} 個。曲線那一個要 6 次開始四問，現在 {n} 次。",
        .w4ok: "好",
        .w4field: "去田看看",

        .weLowWeekend: "最近 {w} 週，週末 {a} 天裡記了 {b} 天；平日 {c} 天裡記了 {d} 天。",
        .weLowWeekday: "最近 {w} 週，平日 {c} 天裡記了 {d} 天；週末 {a} 天裡記了 {b} 天。",
        .weQ: "{g}那個時機有出現嗎？",
        .weC1: "{g}作息不一樣，時機沒出現",
        .weC2: "有出現，但被別的事搶走",
        .c3: "不是這個原因",
        .c4: "不確定",
        .skip: "先不回答",
        .aq: "要改哪裡？",
        .weA1: "寫一個{g}用的「不順的時候」",
        .weA2: "把時機換成{g}也會發生的瞬間",
        .aTips: "看「讓開始更容易」",
        .aNone: "先不改",
        .tr1: "最近 {w} 週，旅行中 {a} 天裡記了 {b} 天；在家 {c} 天裡記了 {d} 天。",
        .trQ: "旅行中的時候，卡在哪裡？",
        .trC1: "那個時機沒出現",
        .trC2: "最小一步帶不走",
        .trA2: "寫「不順的時候」",
        .lv1: "最近 8 週跳過 {n} 次，其中 {k} 次是「{reason}」。",
        .lvAQ: "要不要改點什麼？",
        .lvA1: "換一個那種日子也會出現的時機",
        .lvA2: "把最小一步縮到那種日子也做得到",
        .lvA3: "寫「不順的時候」",
        .noteQ: "想寫的話，一句就好",
        .noteOK: "記下",
        .notSure: "好，先記著。之後還是這樣，這裡會再說一次。",
        .mem1: "上次選的是「{cause}」。",
        .mem2: "上次試過「{change}」，結論是「{conclusion}」。",
        .tryQ: "要不要試兩週？{end} 之後的週回顧，再看一次{g}記了幾天。",
        .tryYes: "好，試試看",
        .tryNo: "先不要",
        .tryOK: "好，{end} 之後再看。",
        .done: "記下了。",
        .exp1: "試兩週到了。試的這兩週，{g} {a} 天裡記了 {b} 天；試之前 {c} 天裡記了 {d} 天。",
        .exp2: "天數還少，這樣的差距可能是剛好。",
        .exp3: "這兩週沒有可以比的{g}。",
        .exp4: "這兩週又改過習慣。",
        .expQ: "你覺得有用嗎？",
        .expKeep: "有用，留著",
        .expSame: "好像沒差",
        .expAgain: "再看兩週",
        .expAgainOK: "好，{end} 之後再看一次。",
        .chgBackup: "{g}用的『不順的時候』",
        .chgTrigger: "換時機",
        .chgTips: "讓開始更容易",

        .d1: "種下去那天 {date}，到今天 {n} 天。三個訊號有兩個通過就算長好了。",
        .d1next: "挖出來之後，下一個是「{next}」。",
        .d2: "最近三次相差 0.5 以內",
        .d2few: "最近三次相差 0.5 以內，至少要 6 次（現在 {n} 次）",
        .d2stale: "最近三次相差 0.5 以內；最近一次在 {date}，再做一次就會重新看",
        .d2spread: "最近三次相差 0.5 以內，而且要在三週內做完",
        .d3: "最近最忙、出遠門或不舒服的那週，有做最小一步，而且沒怎麼掙扎",
        .d3yes: "{date} 回答：有，照做了",
        .d3no: "{date} 回答：還沒遇到或那週掉了",
        .d4: "兩週不記，看做的天數有沒有變少",
        .d4running: "放手測試進行中，到 {date}",
        .d4result: "放手兩週，回想做了 {r} 天（之前兩週 {p} 天）",
        .d4unsure: "放手兩週，記不清楚做了幾天",
        .d5: "有些事會一直需要你出力，這也沒關係。要不要看看時機和最小一步？",
        .d5button: "看我的習慣",
        .d6do: "做這週的開始四問",
        .d6week: "這週的田",
        .d7title: "這幾週記了幾天",
        .d7row: "{n} 天",
        .d7leave: "{n} 天 · 跳過 {m}",
        .d7few: "種下去第 {d} 天，滿一週就列出來。",
        .d7first: "種下去第 1 週，{d} 天裡記了 {n} 天",
        .d7empty: "沒有紀錄",
        .d7letgo: "放手測試",
        .d7changed: "改過時機",
        .d7today: "（今天還沒記）",
        .d7foot: "實心是記了，空心是跳過，滿格是 7 天。沒有紀錄的週不畫。",
        .d8title: "漏掉的日子有沒有規律",
        .d8counts: "最近 {w} 週：平日 {c} 天裡記了 {d} 天；週末 {a} 天裡記了 {b} 天。",
        .d8below: "差距在平常的起伏裡，先不下結論。",
        .d8over: "兩組差得比平常的起伏大。",
        .d8few: "要再大約 {k} 週，平日和週末就各有 10 天可以比。",
        .d8pause: "停下來的那 {g} 天不算進來。",
        .d8travel: "旅行中 {a} 天裡記了 {b} 天；在家 {c} 天裡記了 {d} 天。",
        .d8travelFew: "旅行中的日子還不到 10 天，先不比。",
        .d8leaves: "跳過 {n} 次：{list}",
        .d8noReason: "沒寫原因",
        .d9: "試兩週：{change}，到 {date}。",
        .d9due: "試兩週到了，打開這週的田看結果。",
        .d9stop: "先不試了",
        .d9look: "看這週的田",

        .f1q: "這週做得多嗎？",
        .f1a: "{n}，平常 {lo} 到 {hi} 天",
        .f1same: "{n}，平常 {lo} 天",
        .f1days: "{n} 天",
        .f1none: "還沒記",
        .f1from: "{k}週前",
        .f1now: "這週",
        .f2q: "哪幾天常漏掉？",
        .f2flat: "看不出差別",
        .f2count: "{a} 天做了 {b} 天",
        .f3q: "不用想就會做了嗎？",
        .f3up: "越來越不用想",
        .f3flat: "差不多",
        .f3low: "還要逼自己",
        .f3down: "最近比較要逼自己",
        .f3mixed: "每次不太一樣",
        .f3top: "不用想",
        .f3bottom: "要逼自己",
        .f4q: "跳過都因為什麼？",
        .f4item: "{reason} {k} 次",
        .fewOn: "{date}看得到{what}",
        .fewSoon: "再記幾天就看得到",
        .fewWeek: "這週做得多不多",
        .fewGap: "哪幾天常漏掉",
        .fewEase: "是不是不用想就會做",

        .p2: "這個理由第 {k} 次了。",
        .p3: "這兩週，大概有幾天做了「{floor}」？",
        .p3unsure: "記不清楚",
        .p3button: "記下來",
        .p3disabled: "先點一個天數",
        .p4pass: "沒有明顯變少。",
        .p4fail: "比之前少一些，先繼續記。",
        .p4unsure: "這次先不算。",
    ]

    /// 照編號取字，填空
    static func t(_ id: CopyID, _ args: [String: CustomStringConvertible] = [:]) -> String {
        var s = table[id] ?? ""
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v.description) }
        return s
    }

    /// 平日或週末（組名）
    static func groupName(_ g: String) -> String { g == "weekday" ? "平日" : "週末" }

    // MARK: 觀察的選項

    struct Option: Identifiable, Equatable {
        let code: String
        let text: String
        var id: String { code }
    }

    /// 問原因的選項（不含跳過）
    static func causes(_ kind: Insight.Kind, low: String?) -> [Option] {
        switch kind {
        case .weekend:
            let g = groupName(low ?? "weekend")
            return [Option(code: "no_trigger", text: t(.weC1, ["g": g])),
                    Option(code: "crowded", text: t(.weC2)),
                    Option(code: "not_this", text: t(.c3)),
                    Option(code: "not_sure", text: t(.c4))]
        case .travel:
            return [Option(code: "no_trigger", text: t(.trC1)),
                    Option(code: "not_portable", text: t(.trC2)),
                    Option(code: "not_this", text: t(.c3)),
                    Option(code: "not_sure", text: t(.c4))]
        case .leaveReason:
            return []
        }
    }

    /// 依原因列的做法（不含「先不改」）。不給做法的原因回空陣列
    static func actions(_ kind: Insight.Kind, cause: String?, low: String?) -> [Option] {
        let g = groupName(low ?? "weekend")
        switch kind {
        case .weekend:
            switch cause {
            case "no_trigger":
                return [Option(code: "backup", text: t(.weA1, ["g": g])),
                        Option(code: "trigger", text: t(.weA2, ["g": g]))]
            case "crowded":
                return [Option(code: "tips", text: t(.aTips)),
                        Option(code: "backup", text: t(.weA1, ["g": g]))]
            default:
                return []
            }
        case .travel:
            switch cause {
            case "no_trigger", "not_portable":
                return [Option(code: "backup", text: t(.trA2))]
            default:
                return []
            }
        case .leaveReason:
            return [Option(code: "trigger", text: t(.lvA1)),
                    Option(code: "floor", text: t(.lvA2)),
                    Option(code: "backup", text: t(.lvA3))]
        }
    }

    /// 原因代碼 → 她當時看到的字（W-MEM-1 用）
    static func causeLabel(_ kind: Insight.Kind, cause: String, low: String?) -> String? {
        causes(kind, low: low).first(where: { $0.code == cause })?.text
    }

    /// 試兩週的做法 → 一句短的（D-9、W-MEM-2 用）
    static func changeLabel(_ change: String, group: String) -> String {
        switch change {
        case "backup": return t(.chgBackup, ["g": groupName(group)])
        case "trigger": return t(.chgTrigger)
        default: return t(.chgTips)
        }
    }

    static func conclusionLabel(_ c: String) -> String? {
        switch c {
        case "keep": return t(.expKeep)
        case "no_difference": return t(.expSame)
        case "again": return t(.expAgain)
        default: return nil
        }
    }

    /// 掃禁用詞用：這個檔與 GlanceCopy 的每一句
    static var everyLine: [(id: String, text: String)] {
        CopyID.allCases.map { ($0.rawValue, table[$0] ?? "") }
            + GlanceCopy.ID.allCases.map { ($0.rawValue, GlanceCopy.table[$0] ?? "") }
    }

    /// 07 用字規則的禁用詞（分析頁書 3-7＋薯記機制表 2-5）
    static let forbidden: [String] = [
        "只", "才", "僅", "竟然", "！", "!", "⚠", "💪", "🔥",
        "應該", "必須", "記得", "別再", "加油",
        "放棄", "失敗", "偷懶", "分心",
        "專注力", "效率", "表現",
        "自律", "好棒", "你是", "變差",
        "平均", "連續", "比上月", "比上週", "%", "％",
        "完成", "達成", "成功",
        "21 天", "66 天", "streak", "斷", "前功盡棄", "白費", "重新開始",
        "意志力", "毅力", "決心", "每天進步", "戒掉", "多巴胺", "科學證實", "保證",
    ]
}
