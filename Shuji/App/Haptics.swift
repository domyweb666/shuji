import UIKit

/// 原型只能用 Safari 的開關觸覺做一種震動；原生版分三種。
enum Haptic {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// 換分頁、選分數。一般按鈕不震，震動留給有意義的時刻
    static func select() {
        selection.selectionChanged()
    }

    /// 移除、撤銷、清除
    static func remove() {
        light.impactOccurred()
    }

    /// 出錯（讀不出來、AI 沒回來）。畫面上一定同時有一句怎麼辦
    static func error() {
        notify.notificationOccurred(.error)
    }

    /// 按下去
    static func press() {
        light.prepare()
        light.impactOccurred()
    }

    /// 按滿一秒半，記了一節
    static func thunk() {
        rigid.impactOccurred(intensity: 1.0)
    }

    /// 回來那一節開花、種下去、挖地瓜
    static func bloom() {
        notify.notificationOccurred(.success)
    }
}
