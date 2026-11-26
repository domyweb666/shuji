import UIKit
import VeggieKit

/// 原型只能用 Safari 的開關觸覺做一種震動；原生版分三種。
enum Haptic {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    /// 換分頁、選分數。一般按鈕不震，震動留給有意義的時刻
    static func select() {
        guard VeggieHaptics.isEnabled else { return }
        selection.selectionChanged()
    }

    /// 移除、撤銷、清除
    static func remove() {
        guard VeggieHaptics.isEnabled else { return }
        light.impactOccurred()
    }

    /// 出錯（讀不出來、AI 沒回來）。畫面上一定同時有一句怎麼辦
    static func error() {
        guard VeggieHaptics.isEnabled else { return }
        notify.notificationOccurred(.error)
    }

    /// 按下去（HoldButton 開始按住時叫）。順便把按滿那下要用的 rigid 先準備好，
    /// 一秒半後 thunk() 震的時候馬達已經醒著（效能審查 2026-11-26 第二節）
    static func press() {
        guard VeggieHaptics.isEnabled else { return }
        light.impactOccurred()
        rigid.prepare()
    }

    /// 按滿一秒半，記了一節（TodayView.recordNode 叫，rigid 已在 press() 準備好）
    static func thunk() {
        guard VeggieHaptics.isEnabled else { return }
        rigid.impactOccurred(intensity: 1.0)
    }

    /// 回來那一節開花、種下去、挖地瓜
    static func bloom() {
        guard VeggieHaptics.isEnabled else { return }
        notify.notificationOccurred(.success)
    }
}
