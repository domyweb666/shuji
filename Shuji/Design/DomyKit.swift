import SwiftUI

// Domy Design System 的 SwiftUI 版元件（照 domy-design/src/components 的規格）。
// 套件目前只有 Swift 代號、沒有 Swift 元件，所以先在薯記本地組；之後第二款原生 App 也要用，再搬進套件。

// MARK: 字級、陰影、按下效果

extension View {
    /// 套 Domy 字級（跟著系統字級縮放，含中文行高）
    func domyType(_ style: DomyTypeStyle) -> some View {
        font(style.font).lineSpacing(style.lineSpacing)
    }

    func domyShadow(_ e: DomyShadow) -> some View {
        shadow(color: Theme.shadow.opacity(e.opacity), radius: e.radius, x: 0, y: e.y)
    }

    /// 輸入框外觀：標籤放框外，框是白底細邊；正在打字變產品色，出錯變紅
    func domyField(focused: Bool = false, error: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Rd.md, style: .continuous)
        let border = error ? Theme.danger : (focused ? Theme.accent : Theme.fieldBorder)
        return self
            .domyType(Ty.body)
            .foregroundStyle(Theme.fg)
            .tint(Theme.accent)
            .padding(.horizontal, Sp.s4)
            .padding(.vertical, Sp.s3)
            .frame(minHeight: Sz.field)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: (error || focused) ? Sz.hairline * 1.5 : Sz.hairline))
    }
}

/// 一般按下：縮小一點；開了「減少動態」就改成變淡
struct DomyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .scaleEffect(down && !reduceMotion ? DomyTokens.Motion.pressScale : 1)
            .opacity(down && reduceMotion ? DomyTokens.Motion.pressedOpacity : 1)
            .animation(.easeOut(duration: DomyTokens.Motion.pressDuration), value: down)
    }
}

/// 列按下去整列變淡灰
struct DomyRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surfaceMuted : Color.clear)
    }
}

// MARK: 按鈕

/// 一個畫面最多一顆 primary。危險操作用 destructive，不用產品色。
/// 停用時請換字（例：「四題都點一下才能記」），不要只靠顏色變淡。
struct DomyButton: View {
    enum Variant { case primary, secondary, plain, quiet, destructive }
    enum Size { case regular, compact }

    var title: String
    var variant: Variant
    var size: Size
    var fullWidth: Bool
    var disabled: Bool
    var action: () -> Void

    init(_ title: String, variant: Variant = .primary, size: Size = .regular,
         fullWidth: Bool? = nil, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.size = size
        self.fullWidth = fullWidth ?? (size == .regular && variant != .plain && variant != .quiet)
        self.disabled = disabled
        self.action = action
    }

    private var isText: Bool { variant == .plain || variant == .quiet }

    private var colors: (bg: Color, fg: Color) {
        if disabled { return (isText ? .clear : Theme.surfaceMuted, Theme.disabled) }
        switch variant {
        case .primary: return (Theme.accent, Theme.onAccent)
        case .secondary: return (Theme.surfaceMuted, Theme.fg)
        case .plain: return (.clear, Theme.strong)
        case .quiet: return (.clear, Theme.fg2)
        case .destructive: return (Theme.dangerSoft, Theme.danger)
        }
    }

    var body: some View {
        Button {
            if variant == .primary { Haptic.select() }
            action()
        } label: {
            label
        }
        .buttonStyle(DomyPressStyle())
        .disabled(disabled)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var label: some View {
        let c = colors
        let height = size == .compact ? Sz.buttonCompact : Sz.button
        if isText {
            // 文字按鈕可以換行（長句提示），可點範圍至少 44
            Text(title)
                .domyType(size == .compact ? Ty.subheadline : Ty.callout)
                .fontWeight(variant == .plain ? .semibold : .regular)
                .foregroundStyle(c.fg)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Sp.s2)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Sz.touch)
                .contentShape(Rectangle())
        } else {
            Text(title)
                .domyType(size == .compact ? Ty.callout : Ty.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(c.fg)
                .padding(.horizontal, size == .compact ? Sp.s4 : Sp.s6)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(c.bg, in: Capsule())
                .frame(minHeight: Sz.touch)
                .contentShape(Capsule())
        }
    }
}

// MARK: 畫面外框

private struct DomyBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = Sp.s8
}

extension EnvironmentValues {
    /// 捲動內容底部要留多少（有懸浮分頁列的頁面由 RootView 設成 Theme.tabBarClearance）
    var domyBottomInset: CGFloat {
        get { self[DomyBottomInsetKey.self] }
        set { self[DomyBottomInsetKey.self] = newValue }
    }
}

/// 畫面外框：畫布色、左右 20 邊距、大標題、區塊之間 24
struct DomyScreen<Trailing: View, Content: View>: View {
    var title: String?
    var sub: String?
    var trailing: Trailing
    var content: Content
    @Environment(\.domyBottomInset) private var bottomInset

    init(title: String? = nil, sub: String? = nil,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.sub = sub
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Sp.s6) {
                if let title {
                    DomyHeader(title: title, sub: sub) { trailing }
                }
                content
            }
            .padding(.horizontal, Sz.screenMargin)
            .padding(.top, Sp.s2)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: Theme.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
    }
}

extension DomyScreen where Trailing == EmptyView {
    init(title: String? = nil, sub: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, sub: sub, trailing: { EmptyView() }, content: content)
    }
}

/// 大標題＋一行副標，右邊可以放一個小東西（例：旅行中）
struct DomyHeader<Trailing: View>: View {
    var title: String
    var sub: String?
    var trailing: Trailing

    init(title: String, sub: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.sub = sub
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Sp.s3) {
            VStack(alignment: .leading, spacing: Sp.s1) {
                Text(title)
                    .domyType(Ty.largeTitle)
                    .foregroundStyle(Theme.fg)
                    .accessibilityAddTraits(.isHeader)
                if let sub {
                    Text(sub)
                        .domyType(Ty.subheadline)
                        .foregroundStyle(Theme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension DomyHeader where Trailing == EmptyView {
    init(title: String, sub: String? = nil) {
        self.init(title: title, sub: sub) { EmptyView() }
    }
}

// MARK: 分組

/// 分組：標題＋一張白卡＋卡下的說明。相關的列放進同一個 Section，不要每列各包一張卡。
struct DomySection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s2) {
            if let title { SectionTitle(title) }
            Card { content }
            if let footer, !footer.isEmpty { Foot(footer) }
        }
    }
}

/// 設定列：開關
struct DomyToggleRow: View {
    var label: String
    var mini: String? = nil
    @Binding var isOn: Bool
    var disabled: Bool = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: Sp.s1 / 2) {
                Text(label).domyType(Ty.body).foregroundStyle(Theme.fg)
                if let mini {
                    Text(mini).domyType(Ty.footnote).foregroundStyle(Theme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
        .disabled(disabled)
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s2)
        .frame(minHeight: Sz.row)
        .opacity(disabled ? DomyTokens.Motion.pressedOpacity : 1)
    }
}

/// 設定列：產品色膠囊（淡底＋深字），點了開選單
struct DomyPickerRow<V: Hashable>: View {
    var label: String
    var options: [V]
    @Binding var selection: V
    var title: (V) -> String

    var body: some View {
        HStack(spacing: Sp.s3) {
            Text(label).domyType(Ty.body).foregroundStyle(Theme.fg)
            Spacer(minLength: 0)
            Menu {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { v in Text(title(v)).tag(v) }
                }
            } label: {
                HStack(spacing: Sp.s2) {
                    Text(title(selection)).domyType(Ty.callout)
                    Image(systemName: "chevron.up.chevron.down").font(Ty.caption.font)
                }
                .foregroundStyle(Theme.strong)
                .padding(.horizontal, Sp.s3)
                .frame(height: Sz.pickerHeight)
                .background(Theme.soft, in: Capsule())
                .padding(.vertical, Sp.s1)
                .contentShape(Capsule())
            }
            .accessibilityLabel("\(label)：\(title(selection))")
            .accessibilityHint("點兩下更改")
        }
        .padding(.horizontal, Sp.s4)
        .frame(minHeight: Sz.row)
    }
}

// MARK: 數字

struct DomyStat: Identifiable {
    var value: String
    var unit: String? = nil
    var label: String
    var id: String { label }
}

/// 2 欄統計數字，Tint 淡底。數字用 Title 1，單位縮一級
struct DomyStatGrid: View {
    var items: [DomyStat]

    private var rows: [[DomyStat]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Rd.xl, style: .continuous)
        VStack(alignment: .leading, spacing: Sp.s4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: Sp.s2) {
                    ForEach(row) { cell($0) }
                    if row.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) } // domy-ignore: 單數格補空位
                }
            }
        }
        .padding(Sp.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tint, in: shape)
        .overlay(shape.strokeBorder(Theme.soft, lineWidth: Sz.hairline))
    }

    private func cell(_ it: DomyStat) -> some View {
        VStack(alignment: .leading, spacing: Sp.s1 / 2) {
            (Text(it.value).font(Ty.title1.font) + Text(it.unit.map { " " + $0 } ?? "").font(Ty.headline.font))
                .foregroundStyle(Theme.fg)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(it.label).domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(it.label)：\(it.value)\(it.unit ?? "")")
    }
}

/// 一行就講完的摘要
struct DomyInfoStrip: View {
    var text: String

    var body: some View {
        Text(text)
            .domyType(Ty.subheadline)
            .foregroundStyle(Theme.fg2)
            .multilineTextAlignment(.center)
            .padding(.vertical, Sp.s2)
            .padding(.horizontal, Sp.s4)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Rd.md, style: .continuous))
            .frame(maxWidth: .infinity)
    }
}

/// 空狀態：說清楚這裡會出現什麼
struct DomyEmptyState: View {
    var icon: String? = nil
    var title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: Sp.s3) {
            if let icon {
                Image(systemName: icon)
                    .font(Ty.title2.font)
                    .foregroundStyle(Theme.accent)
                    .frame(width: Sz.emptyIcon, height: Sz.emptyIcon)
                    .background(Theme.soft, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(title)
                .domyType(Ty.headline)
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .domyType(Ty.subheadline)
                    .foregroundStyle(Theme.fg2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Sp.s6)
        .padding(.horizontal, Sp.s6)
    }
}

// MARK: 分頁列

/// 懸浮膠囊分頁列。選中的那格：淡產品色底＋深產品色字＋實心圖示
struct DomyTabBar: View {
    struct Item {
        let title: String
        let icon: String
    }

    var items: [Item]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: Sp.s1) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let on = i == selection
                Button {
                    guard !on else { return }
                    Haptic.select()
                    withAnimation(.easeInOut(duration: DomyTokens.Motion.transition)) { selection = i }
                } label: {
                    VStack(spacing: Sp.s1 / 2) {
                        Image(systemName: on ? item.icon + ".fill" : item.icon)
                            .font(Ty.title3.font)
                            .frame(height: Sp.s6)
                        Text(item.title)
                            .font(Ty.caption.font.weight(on ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(on ? Theme.strong : Theme.fg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(on ? Theme.soft : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(Sp.s1 + Sp.s1 / 2)
        .frame(width: Sz.tabBarWidth, height: Sz.tabBar)
        .background(Theme.surface, in: Capsule())
        .domyShadow(DomyTokens.Elevation.level2)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
    }
}

// MARK: 1 到 7 的分數

/// 開始四問用的分數列。沒有預設值，點了才算數
struct ScalePicker: View {
    var title: String
    @Binding var selection: Int
    var range: ClosedRange<Int> = 1...7

    var body: some View {
        HStack(spacing: Sp.s1) {
            ForEach(Array(range), id: \.self) { n in
                let on = n == selection
                Button {
                    Haptic.select()
                    selection = n
                } label: {
                    Text("\(n)")
                        .domyType(Ty.callout)
                        .monospacedDigit()
                        .foregroundStyle(on ? Theme.onAccent : Theme.fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: Sz.buttonCompact)
                        .background(on ? Theme.accent : Theme.surfaceMuted, in: Capsule())
                        .frame(minHeight: Sz.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DomyPressStyle())
                .accessibilityLabel("\(n)")
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
