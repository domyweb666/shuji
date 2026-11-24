import SwiftUI
import VeggieKit

// 蔬菜家族共用元件（VeggieKit）在這個 app 的那一份設定（多米 iOS 開發準則 3-10）。名字、信箱、網址只寫在這裡。

extension VeggieConfig {
    static let shuji = VeggieConfig(
        name: "薯記",
        slug: "shuji",
        tagline: "把一個習慣接到每天的固定瞬間",
        // 填了 Apple ID 才有評分、分享
        appStoreID: nil,
        // 家族共用的回饋信箱（VeggieKit README）
        supportEmail: "charlie@domyweb.org",
        // 隱私權政策網頁還沒有，先不列
        privacyURL: nil
    )
}

extension VeggieStyle {
    static let shuji = VeggieStyle(
        textPrimary: Theme.fg, textSecondary: Theme.fg2, textTertiary: Theme.fg3,
        accent: Theme.accent, destructive: Theme.danger, canvas: Theme.canvas, surface: Theme.surface,
        body: Ty.body.font, headline: Ty.headline.font, subheadline: Ty.subheadline.font, footnote: Ty.footnote.font,
        rowHeight: Sz.row
    )
}
