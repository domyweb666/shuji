import Foundation

/// 全部文案照原型搬，一字不改。
enum Phrases {
    static let done = [
        "一節。", "根紮下去了。", "今天這一下，算數。", "開關按到了。", "藤又往前一點。",
        "做了就好，做多少是另一件事。", "記下了，去忙吧。", "土裡的事，慢慢長。", "又一條根。",
        "今天的份，到手。", "小到不像話，但有算。", "這一下不用想，就對了。", "藤不急，你也不用急。",
        "一節一節來。", "按到了，收工。", "今天也有出現。", "根比葉子重要。", "最小的一步，最難漏。",
        "開關一響，手就動了。", "今天的藤，長好了。", "看得到的是葉子，長的是根。", "好，明天同一個時候見。",
    ]

    static let returns = [
        "回來了。", "藤沒有枯，接著長。", "漏掉的那天不用補，今天這一下就夠。", "回來的那一節才會開花。",
        "根都還在。", "從這一節接上。", "停了一下而已。", "接回來了。", "這朵花是給回來的人的。",
        "回來，比沒漏過還重要。",
    ]

    /// 讓開始更容易：原型設定頁那三條，現在住在「卡住了」那條路徑
    static let tips = [
        "前一晚把東西準備好，開關一出現只剩一個動作",
        "開關那一刻最常搶走你的東西，放到另一個房間",
        "要做的決定（寫哪篇、練哪個）前一晚就決定",
    ]

    static let floorExamples = ["打開檔案寫一句", "坐上蒲團按計時器", "換上球鞋出門", "讀一頁書", "做一下伸展"]
    static let triggerExamples = ["起床喝完第一杯水", "刷完牙", "咖啡端上桌", "坐到書桌前", "闔上筆電", "上床前"]

    /// 同原型：用日序數取餘，同一天看到的句子固定
    static func phrase(for day: DayKey, isReturn: Bool) -> String {
        let n = day.dayNumber
        if isReturn { return returns[((n % returns.count) + returns.count) % returns.count] }
        return done[((n % done.count) + done.count) % done.count]
    }

    /// 「開始四問」的四句（SRBAI 自動化量表）
    static func reviewQuestions(floor: String) -> [String] {
        [
            "「\(floor)」這件事的開始，是我自動會做的。",
            "我不用刻意記得，就會開始。",
            "我不用想，就會開始。",
            "我意識到之前，就已經開始了。",
        ]
    }
}

/// 原型裡的 NEG / FOOD 兩條規則
enum Wording {
    static let negativePattern = "[不別戒]|少[吃滑喝看玩]|停止|避免|減少"
    static let foodPattern = "減重|減肥|卡路里|熱量|少吃|斷食|體重"

    /// 「不做某件事」沒辦法每天重複，最小一步不能是否定句
    static func isNegative(_ s: String) -> Bool {
        s.range(of: negativePattern, options: .regularExpression) != nil
    }

    /// 跟飲食、體重有關的目標，這個 app 可能不適合
    static func isFood(_ s: String) -> Bool {
        s.range(of: foodPattern, options: .regularExpression) != nil
    }

    static let negativeWarning = "「就」後面要放一個做得出來的動作。「不做某件事」沒辦法每天重複，換成你要做什麼，例如「想滑手機時，就站起來倒杯水」。"
    static let tooLongWarning = "這比較像平常想做到的量。最小一步要小到最糟的一天也做得到，兩分鐘內做完。"
    static let foodWarning = "跟飲食、體重有關的目標，這個 app 可能不適合。"
}
