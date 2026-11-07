import SwiftUI

// 對應原型的 .card / .row / .h2 / .foot / .btn / .link / .chip / .sig 這些樣式

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// 列與列之間的細線，左邊縮進 18
struct RowSep: View {
    var body: some View {
        Rectangle()
            .fill(Theme.sep)
            .frame(height: 0.5)
            .padding(.leading, Theme.rowInset)
    }
}

struct RowLabel: View {
    var text: String
    var value: String? = nil
    var mini: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                if let mini {
                    Text(mini).font(.footnote).foregroundStyle(Theme.fg2)
                }
            }
            Spacer(minLength: 0)
            if let value {
                Text(value)
                    .foregroundStyle(Theme.fg2)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.rowHeight)
    }
}

struct RowButton: View {
    var text: String
    var value: String? = nil
    var chevron: Bool = true
    var color: Color = Theme.fg
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(text).foregroundStyle(color)
                Spacer(minLength: 0)
                if let value {
                    Text(value).foregroundStyle(Theme.fg2).monospacedDigit()
                }
                if chevron {
                    Text("›").font(.system(size: 20)).foregroundStyle(Theme.fg3)
                }
            }
            .padding(.horizontal, Theme.rowInset)
            .frame(minHeight: Theme.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

struct BigTitle: View {
    var title: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.weight(.bold))
            if let sub {
                Text(sub).font(.body).foregroundStyle(Theme.fg2)
            }
        }
    }
}

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title2.weight(.bold))
            .padding(.leading, 2)
            .padding(.bottom, -10)
    }
}

struct Foot: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.fg2)
            .padding(.horizontal, Theme.rowInset)
            .padding(.top, -14)
    }
}

struct Chip: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accentSoft, in: Capsule())
    }
}

struct PrimaryButton: View {
    var title: String
    var ghost: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(ghost ? Theme.fg : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(ghost ? Theme.fill : Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LinkButton: View {
    var title: String
    var quiet: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(quiet ? .system(size: 14) : .subheadline.weight(.semibold))
                .foregroundStyle(quiet ? Theme.fg2 : Theme.accent)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }
}

struct PillButton: View {
    var title: String
    var primary: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primary ? Color.white : Theme.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(primary ? Theme.accent : Theme.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 「長好了嗎」前面那顆圈，過了就填色打勾
struct SignalDot: View {
    var ok: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(ok ? Theme.accent : Theme.fg3, lineWidth: 1.5)
            if ok {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel(ok ? "已通過" : "還沒")
    }
}

/// 警告框（首次設定用）
struct WarnBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 開關句卡片：如果〔開關〕，我就〔最小一步〕。
struct SwitchCard: View {
    var trigger: String
    var floor: String
    var dim: Bool = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("開關").font(.footnote).foregroundStyle(Theme.fg2)
                (Text("如果") + Text(trigger).bold() + Text("，我就") + Text(floor).bold() + Text("。"))
                    .font(.title2)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 20, leading: 20, bottom: 22, trailing: 20))
        }
        .opacity(dim ? 0.55 : 1)
    }
}

/// 一排可換行的小籤
struct ChipFlow: View {
    var items: [String]
    var accent: Bool = false
    var pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { pick(item) } label: {
                    Text(item)
                        .font(.system(size: 14, weight: accent ? .semibold : .regular))
                        .foregroundStyle(accent ? Theme.accent : Theme.fg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(accent ? Theme.accentSoft : Theme.fill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

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

/// 竹籃裡那顆地瓜（原型的 potatoSVG）
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

struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .allowsHitTesting(false)
    }
}
