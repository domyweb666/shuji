import SwiftUI
import UIKit

// 介面色、字級、間距、圓角全部來自 Domy Design System（Shared/DomyTokens.swift，從 domy-design 複製，不要手改）。
// 畫面程式只准用這裡的代號，不寫色碼、字級、間距數字。田園畫布是插畫，自己的顏色留在 Garden。

typealias Sp = DomyTokens.Space
typealias Ty = DomyTokens.TypeScale
typealias Sz = DomyTokens.Size
typealias Rd = DomyTokens.Radius

enum Theme {
    /// 薯記的產品色：梅紫
    static let brand = DomyTheme.plum

    static let canvas = brand.canvas
    static let surface = DomyTokens.Neutral.surface
    static let surfaceMuted = DomyTokens.Neutral.surfaceMuted
    static let separator = DomyTokens.Neutral.separator
    static let fieldBorder = DomyTokens.Neutral.fieldBorder
    static let fg = DomyTokens.Neutral.textPrimary
    static let fg2 = DomyTokens.Neutral.textSecondary
    static let fg3 = DomyTokens.Neutral.textTertiary
    static let disabled = DomyTokens.Neutral.textDisabled
    static let danger = DomyTokens.Neutral.destructive
    static let dangerSoft = DomyTokens.Neutral.destructiveSoft
    static let shadow = DomyTokens.Neutral.shadow

    static let accent = brand.accent
    static let onAccent = brand.onAccent
    static let strong = brand.strong
    static let soft = brand.soft
    static let tint = brand.tint
    static let bright = brand.bright
    static let onBright = brand.onBright

    /// 懸浮分頁列底下要讓出來的高度（不含安全區，ScrollView 自己會算）
    static let tabBarClearance = Sz.tabBarBottom + Sz.tabBar + Sp.s4
    /// 內容最寬多少（iPad、橫放時不要拉滿）
    static let contentMaxWidth: CGFloat = 560 // domy-ignore: 閱讀寬度上限，套件沒有這個代號

    /// 地瓜藤那塊畫布用的顏色（插畫，不走介面代號）
    struct Garden {
        let soil: Color
        let soilDeep: Color
        let grain: Color
        let leaf: Color
        let leafDark: Color
        let vine: Color
        let root: Color
        let flower: Color
        let flowerCore: Color
    }

    static let gardenLight = Garden(
        soil: hex(0xB88A63), soilDeep: hex(0x94673F),
        grain: Color(red: 70 / 255, green: 40 / 255, blue: 15 / 255).opacity(0.18),
        leaf: hex(0x4E9F3D), leafDark: hex(0x2F7A2A), vine: hex(0x6B8E3A),
        root: Color(red: 1, green: 236 / 255, blue: 214 / 255).opacity(0.75),
        flower: hex(0xD9A7BD), flowerCore: hex(0x8B5A71)
    )

    static let gardenDark = Garden(
        soil: hex(0x5A3D27), soilDeep: hex(0x3F2919),
        grain: Color.black.opacity(0.28),
        leaf: hex(0x4A9339), leafDark: hex(0x2C6A26), vine: hex(0x5C7C33),
        root: Color(red: 1, green: 226 / 255, blue: 196 / 255).opacity(0.45),
        flower: hex(0xD7A3BB), flowerCore: hex(0x74485D)
    )

    static func garden(_ scheme: ColorScheme) -> Garden { scheme == .dark ? gardenDark : gardenLight }

    /// 給地瓜小圖（深淺自動切換）
    static let vineDynamic = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? uiHex(0x5C7C33) : uiHex(0x6B8E3A)
    })
    static let leafDynamic = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? uiHex(0x4A9339) : uiHex(0x4E9F3D)
    })

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func uiHex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
