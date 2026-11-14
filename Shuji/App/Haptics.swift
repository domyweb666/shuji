import UIKit

/// 原型只能用 Safari 的開關觸覺做一種震動；原生版分三種。
enum Haptic {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// 主要按鈕、換分頁（Domy 規格：輕輕一下）
    static func select() {
        selection.selectionChanged()
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

    /// 回來那一節開花
    static func bloom() {
        notify.notificationOccurred(.success)
    }
}
