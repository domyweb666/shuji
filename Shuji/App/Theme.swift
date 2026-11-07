import SwiftUI
import UIKit

/// 色票照原型的 CSS 變數。介面色直接用 iOS 系統色（原型本來就是抄系統色），田園色自己定義。
enum Theme {
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let fg = Color(uiColor: .label)
    static let fg2 = Color(uiColor: .secondaryLabel)
    static let fg3 = Color(uiColor: .tertiaryLabel)
    static let sep = Color(uiColor: .separator)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let accent = Color(uiColor: .systemPurple)
    static let accentSoft = Color(uiColor: UIColor { tc in
        UIColor.systemPurple.withAlphaComponent(tc.userInterfaceStyle == .dark ? 0.2 : 0.12)
    })
    static let danger = Color(uiColor: .systemRed)

    static let cardRadius: CGFloat = 26
    static let rowHeight: CGFloat = 56
    static let rowInset: CGFloat = 18

    /// 地瓜藤那塊畫布用的顏色
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
        flower: hex(0xC084E6), flowerCore: hex(0x7B2FA8)
    )

    static let gardenDark = Garden(
        soil: hex(0x5A3D27), soilDeep: hex(0x3F2919),
        grain: Color.black.opacity(0.28),
        leaf: hex(0x4A9339), leafDark: hex(0x2C6A26), vine: hex(0x5C7C33),
        root: Color(red: 1, green: 226 / 255, blue: 196 / 255).opacity(0.45),
        flower: hex(0xC98BEB), flowerCore: hex(0x8A3BB8)
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
