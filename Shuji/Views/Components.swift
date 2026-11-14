import SwiftUI

// 薯記自己的小零件，全部用 Domy 代號組（Theme、Sp、Ty、Sz、Rd）。

/// 白卡：圓角 20，列之間用 RowSep 分開
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Rd.xl, style: .continuous)
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: shape)
            .clipShape(shape)
    }
}

/// 卡片裡的內容區塊（不是一列，是一段文字或一組輸入）
struct CardBody<Content: View>: View {
    var spacing: CGFloat = Sp.s2
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Sp.s4)
            .padding(.vertical, Sp.s4)
    }
}

/// 列與列之間 1pt 分隔線，左右各縮 16
struct RowSep: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Sz.hairline)
            .padding(.horizontal, Sp.s4)
    }
}

struct RowLabel: View {
    var text: String
    var value: String? = nil
    var mini: String? = nil

    var body: some View {
        HStack(spacing: Sp.s3) {
            VStack(alignment: .leading, spacing: Sp.s1 / 2) {
                Text(text)
                    .domyType(Ty.body)
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                if let mini {
                    Text(mini)
                        .domyType(Ty.footnote)
                        .foregroundStyle(Theme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let value {
                Text(value)
                    .domyType(Ty.body)
                    .foregroundStyle(Theme.fg2)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
        .frame(minHeight: Sz.row)
    }
}

/// 可以點的列。tone 決定字色：一般、產品色動作、危險
struct RowButton: View {
    enum Tone { case normal, action, danger }

    var text: String
    var value: String? = nil
    var chevron: Bool = true
    var tone: Tone = .normal
    var disabled: Bool = false
    var action: () -> Void

    private var color: Color {
        if disabled { return Theme.disabled }
        switch tone {
        case .normal: return Theme.fg
        case .action: return Theme.strong
        case .danger: return Theme.danger
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Sp.s3) {
                Text(text)
                    .domyType(Ty.body)
                    .fontWeight(tone == .action ? .semibold : .regular)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .domyType(Ty.body)
                        .foregroundStyle(disabled ? Theme.disabled : Theme.fg2)
                        .monospacedDigit()
                }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(Ty.footnote.font.weight(.semibold))
                        .foregroundStyle(Theme.fg3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Sp.s4)
            .padding(.vertical, Sp.s3)
            .frame(minHeight: Sz.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(DomyRowPressStyle())
        .disabled(disabled)
    }
}

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .domyType(Ty.title3)
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, Sp.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 卡片下面的灰色說明
struct Foot: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .domyType(Ty.footnote)
            .foregroundStyle(Theme.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Sp.s4)
    }
}

/// 小標籤（例：旅行中）
struct Chip: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .domyType(Ty.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.strong)
            .padding(.horizontal, Sp.s3)
            .padding(.vertical, Sp.s1 + Sp.s1 / 2)
            .background(Theme.soft, in: Capsule())
    }
}

/// 卡片裡的小灰標題（例：「開關」「你說這是為了」）
struct Eyebrow: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .domyType(Ty.footnote)
            .foregroundStyle(Theme.fg2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 「長好了嗎」前面那顆圈，過了就填色打勾
struct SignalDot: View {
    var ok: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(ok ? Theme.accent : Theme.fg3, lineWidth: Sz.hairline * 1.5)
            if ok {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(Ty.caption.font.weight(.bold))
                    .foregroundStyle(Theme.onAccent)
            }
        }
        .frame(width: Sp.s6, height: Sp.s6)
        .accessibilityLabel(ok ? "已通過" : "還沒")
    }
}

/// 提醒框：淡產品色底（首次設定的措辭提醒、AI 失敗訊息）
struct WarnBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Sp.s2) {
            Image(systemName: "exclamationmark.circle")
                .font(Ty.subheadline.font.weight(.semibold))
                .foregroundStyle(Theme.strong)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Sp.s2) { content }
                .domyType(Ty.subheadline)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Sp.s3)
        .padding(.horizontal, Sp.s4)
        .background(Theme.soft, in: RoundedRectangle(cornerRadius: Rd.md, style: .continuous))
    }
}

/// 開關句卡片：如果〔開關〕，我就〔最小一步〕。整個 app 的主角，用產品色淡底
struct SwitchCard: View {
    var trigger: String
    var floor: String
    var dim: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Rd.xl, style: .continuous)
        VStack(alignment: .leading, spacing: Sp.s2) {
            Text("開關")
                .domyType(Ty.caption)
                .foregroundStyle(Theme.strong)
            (Text("如果") + Text(trigger).bold() + Text("，我就") + Text(floor).bold() + Text("。"))
                .font(.system(Ty.title2.textStyle))
                .lineSpacing(Ty.title2.lineSpacing)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Sp.s5)
        .background(Theme.tint, in: shape)
        .overlay(shape.strokeBorder(Theme.soft, lineWidth: Sz.hairline))
        .opacity(dim ? DomyTokens.Motion.pressedOpacity : 1)
        .accessibilityElement(children: .combine)
    }
}

/// 一排可換行的小籤。accent：產品色（AI 候選、排隊中），否則中性灰
struct ChipFlow: View {
    var items: [String]
    var accent: Bool = false
    var selected: String? = nil
    var pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: Sp.s2) {
            ForEach(items, id: \.self) { item in
                let on = item == selected
                Button { pick(item) } label: {
                    Text(item)
                        .domyType(Ty.subheadline)
                        .fontWeight(accent || on ? .semibold : .regular)
                        .foregroundStyle(on ? Theme.onAccent : (accent ? Theme.strong : Theme.fg))
                        .padding(.horizontal, Sp.s3)
                        .frame(minHeight: Sz.pickerHeight)
                        .background(on ? Theme.accent : (accent ? Theme.soft : Theme.surfaceMuted), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(DomyPressStyle())
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = Sp.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: maxWidth == .infinity ? usedWidth : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 竹籃裡那顆地瓜（原型的 potatoSVG）。插畫，座標照原型
struct PotatoView: View {
    var width: CGFloat = 44

    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            g.scaleBy(x: size.width / 88, y: size.width / 88)

            var vine = Path()
            vine.move(to: CGPoint(x: 20, y: 22))
            vine.addCurve(to: CGPoint(x: 60, y: 14), control1: CGPoint(x: 30, y: 4), control2: CGPoint(x: 52, y: 6))
            g.stroke(vine, with: .color(Theme.vineDynamic), lineWidth: 3)

            var leaf = Path()
            leaf.move(to: CGPoint(x: 58, y: 13))
            leaf.addCurve(to: CGPoint(x: 66, y: 3), control1: CGPoint(x: 50, y: 3), control2: CGPoint(x: 60, y: -3))
            leaf.addCurve(to: CGPoint(x: 72, y: 13), control1: CGPoint(x: 70, y: -3), control2: CGPoint(x: 80, y: 3))
            leaf.closeSubpath()
            g.fill(leaf, with: .color(Theme.leafDynamic))

            var body = g
            body.translateBy(x: 44, y: 38)
            body.rotate(by: .degrees(-8))
            body.fill(Path(ellipseIn: CGRect(x: -36, y: -19, width: 72, height: 38)), with: .color(Theme.accent))

            var shine = g
            shine.translateBy(x: 34, y: 31)
            shine.rotate(by: .degrees(-14))
            shine.fill(Path(ellipseIn: CGRect(x: -14, y: -5, width: 28, height: 10)), with: .color(.white.opacity(0.22)))

            var marks = Path()
            marks.move(to: CGPoint(x: 30, y: 44))
            marks.addQuadCurve(to: CGPoint(x: 42, y: 44), control: CGPoint(x: 36, y: 46))
            marks.move(to: CGPoint(x: 52, y: 40))
            marks.addQuadCurve(to: CGPoint(x: 62, y: 39), control: CGPoint(x: 57, y: 42))
            g.stroke(marks, with: .color(.black.opacity(0.18)), lineWidth: 1.5)
        }
        .frame(width: width, height: width * 60 / 88)
        .accessibilityHidden(true)
    }
}

/// 竹籃裡地瓜的圓底小圖示
struct PotatoBadge: View {
    var body: some View {
        PotatoView(width: Sp.s8)
            .frame(width: Sz.touch, height: Sz.touch)
            .background(Theme.soft, in: Circle())
    }
}

struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .domyType(Ty.subheadline)
            .foregroundStyle(Theme.fg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Sp.s5)
            .padding(.vertical, Sp.s3)
            .background(Theme.surface, in: Capsule())
            .domyShadow(DomyTokens.Elevation.level2)
            .padding(.horizontal, Sz.screenMargin)
            .allowsHitTesting(false)
    }
}
