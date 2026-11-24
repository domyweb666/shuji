import SwiftUI

/// 土裡那顆地瓜的尺寸與外觀。按鈕和記好、跳過、放手的樣子共用，換狀態位置不跳。
struct PotatoBody<Label: View>: View {
    var fill: Color
    /// 外圈跑到哪（0 到 1）
    var ring: CGFloat
    var ringColor: Color
    /// 記好了：1 是烤好剝開，0 是原本的樣子
    var open: CGFloat = 0
    @ViewBuilder var label: Label

    /// 地瓜本體、外圈、整塊佔的大小（插畫，不走代號）
    static var bodySize: CGSize { CGSize(width: 216, height: 124) }
    static var ringSize: CGSize { CGSize(width: 248, height: 156) }
    static var frameSize: CGSize { CGSize(width: 264, height: 196) }
    private let tilt = Angle.degrees(-8)

    var body: some View {
        let size = Self.bodySize
        ZStack {
            ZStack {
                Group {
                    PotatoRing(progress: 1)
                        .stroke(ringColor.opacity(0.45), lineWidth: Sz.heroRingWidth)
                    PotatoRing(progress: ring)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: Sz.heroRingWidth * 2, lineCap: .round))
                }
                .frame(width: Self.ringSize.width, height: Self.ringSize.height)
                .opacity(1 - open)
                Ellipse()
                    .fill(fill)
                    .frame(width: size.width, height: size.height)
                Ellipse()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: size.width * 0.38, height: size.height * 0.22)
                    .offset(x: -size.width * 0.18, y: -size.height * 0.26)
                    .opacity(1 - open)
                PotatoMarks()
                    .stroke(Color.black.opacity(0.18), style: StrokeStyle(lineWidth: Sz.heroRingWidth, lineCap: .round))
                    .frame(width: size.width, height: size.height)
                    .opacity(1 - open)
                // 從中間裂開：先一條縫，再往上下張開
                BakedFlesh()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(x: 0.6 + 0.4 * open, y: max(0.01, open))
                    .opacity(open > 0.02 ? 1 : 0)
            }
            .rotationEffect(tilt)
            Steam()
                .stroke(ringColor, style: StrokeStyle(lineWidth: Sz.heroRingWidth * 1.5, lineCap: .round))
                .offset(y: Sp.s3 * (1 - open))
                .opacity(open)
            label
        }
        .frame(width: Self.frameSize.width, height: Self.frameSize.height)
    }
}

/// 從正上方順時針跑的橢圓圈
struct PotatoRing: Shape {
    var progress: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps = 120
        let n = Int((CGFloat(steps) * max(0, min(1, progress))).rounded())
        guard n > 0 else { return p }
        for i in 0...n {
            let a = Double(i) / Double(steps) * 2 * Double.pi - Double.pi / 2
            let pt = CGPoint(x: rect.midX + rect.width / 2 * CGFloat(cos(a)), y: rect.midY + rect.height / 2 * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// 地瓜皮上的兩道紋
private struct PotatoMarks: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        var p = Path()
        p.move(to: pt(0.24, 0.78))
        p.addQuadCurve(to: pt(0.4, 0.8), control: pt(0.32, 0.86))
        p.move(to: pt(0.64, 0.82))
        p.addQuadCurve(to: pt(0.78, 0.76), control: pt(0.72, 0.84))
        return p
    }
}

/// 跳過：深色的地瓜，理由寫在上面
struct PotatoSkip: View {
    var reason: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PotatoBody(fill: Theme.potatoSkip, ring: 0, ringColor: Theme.potatoRing(scheme)) {
            VStack(spacing: Sp.s1) {
                Text("跳過").domyType(Ty.title1)
                if !reason.isEmpty {
                    Text(reason)
                        .domyType(Ty.callout)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: PotatoBody<EmptyView>.bodySize.width * 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reason.isEmpty ? "今天跳過" : "今天跳過，\(reason)")
    }
}

/// 放手：安靜的淡色
struct PotatoSeal: View {
    var icon: String
    var title: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PotatoBody(fill: Theme.soft, ring: 0, ringColor: Theme.potatoRing(scheme)) {
            VStack(spacing: Sp.s1) {
                Image(systemName: icon).font(Ty.title2.font)
                Text(title).domyType(Ty.headline)
            }
            .foregroundStyle(Theme.strong)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// 烤好剝開的切口（插畫，座標照 Claude Design 選項 C）
private struct BakedFlesh: View {
    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.fill(BakedFlesh.blob([
                (-92, 0), (-67, -32), (-54, -21), (-36, -34), (-17, -47), (4, -28), (23, -38),
                (48, -47), (69, -28), (94, -2), (71, 25), (56, 21), (35, 32),
                (13, 43), (-6, 26), (-29, 36), (-54, 42), (-73, 23), (-92, 0),
            ]), with: .color(Theme.bakedRim))
            g.fill(BakedFlesh.blob([
                (-84, 0), (-63, -26), (-52, -15), (-35, -28), (-17, -40), (4, -23), (23, -32),
                (46, -40), (65, -25), (86, -2), (67, 19), (54, 15), (33, 26),
                (13, 36), (-6, 21), (-27, 30), (-50, 36), (-67, 19), (-84, 0),
            ]), with: .color(Theme.bakedFlesh))
            g.fill(BakedFlesh.blob([
                (-60, 0), (-42, -17), (-29, -9), (-13, -17), (6, -24), (27, -17), (58, -2),
                (33, 13), (17, 9), (0, 17), (-21, 23), (-42, 13), (-60, 0),
            ]), with: .color(Theme.bakedCore))
            var lines = Path()
            lines.move(to: CGPoint(x: -29, y: -2))
            lines.addQuadCurve(to: CGPoint(x: -8, y: 0), control: CGPoint(x: -19, y: 4))
            lines.move(to: CGPoint(x: 13, y: 6))
            lines.addQuadCurve(to: CGPoint(x: 33, y: 2), control: CGPoint(x: 25, y: 0))
            g.stroke(lines, with: .color(Theme.bakedLine.opacity(0.6)), style: StrokeStyle(lineWidth: Sz.heroRingWidth, lineCap: .round))
        }
    }

    /// 起點，之後每三點一段曲線
    private static func blob(_ p: [(Double, Double)]) -> Path {
        var path = Path()
        func pt(_ i: Int) -> CGPoint { CGPoint(x: p[i].0, y: p[i].1) }
        path.move(to: pt(0))
        var i = 1
        while i + 2 < p.count {
            path.addCurve(to: pt(i + 2), control1: pt(i), control2: pt(i + 1))
            i += 3
        }
        path.closeSubpath()
        return path
    }
}

/// 地瓜上面的三道煙
private struct Steam: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (dx, y) in [(-38.0, -62.0), (0.0, -68.0), (38.0, -62.0)] {
            let x = rect.midX + dx
            let b = rect.midY + y
            p.move(to: CGPoint(x: x, y: b))
            p.addQuadCurve(to: CGPoint(x: x, y: b - 15), control: CGPoint(x: x - 10, y: b - 8))
            p.addQuadCurve(to: CGPoint(x: x, y: b - 30), control: CGPoint(x: x + 10, y: b - 22))
        }
        return p
    }
}

/// 按住土裡那顆地瓜一秒半，外圈跑滿就記一節。放開就縮回去。
/// 這是整個 app 唯一的核心動作，刻意要「按住」而不是「點一下」。按著的時候地瓜慢慢脹大。
struct HoldButton: View {
    /// 只給讀屏
    var hint: String
    /// 今天記好了：同一顆地瓜烤好剝開，按了沒反應。用同一個 view，變形才接得起來
    var done = false
    var onComplete: () -> Void

    @GestureState private var pressing = false
    @State private var startTime: Date? = nil
    @State private var releaseTime: Date? = nil
    @State private var releaseProgress: CGFloat = 0
    /// 按滿了：換成「記好了」之前外圈停在滿的，不閃回空圈
    @State private var full = false
    @State private var resetTask: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private static let duration: TimeInterval = 1.5
    private static let resetDuration: TimeInterval = 0.25
    /// 按滿時脹大多少
    private static let swell: CGFloat = 0.08
    private var duration: TimeInterval { HoldButton.duration }
    private var resetDuration: TimeInterval { HoldButton.resetDuration }

    var body: some View {
        TimelineView(.animation(paused: startTime == nil && releaseTime == nil)) { timeline in
            let p = progress(at: timeline.date)
            PotatoBody(fill: pressing && !done ? Theme.strong : Theme.accent, ring: done ? 1 : p,
                       ringColor: Theme.potatoRing(scheme), open: done ? 1 : 0) {
                Text("按住")
                    .domyType(Ty.title1)
                    .tracking(2)
                    .foregroundStyle(Theme.onAccent)
                    .opacity(done ? 0 : 1)
            }
            .scaleEffect(reduceMotion || done ? 1 : 1 + HoldButton.swell * p)
            .animation(reduceMotion ? nil : Feel.open, value: done)
        }
        .animation(Feel.press, value: pressing)
        .contentShape(Ellipse())
        .gesture(
            LongPressGesture(minimumDuration: duration, maximumDistance: 40)
                .updating($pressing) { value, state, _ in state = value && !done }
                .onEnded { _ in complete() }
        )
        .onChange(of: pressing) { _, isPressing in
            if isPressing {
                resetTask?.cancel()
                full = false
                releaseTime = nil
                startTime = Date()
                Haptic.press()
                SoundPlayer.shared.prime()
            } else if let s = startTime {
                // 放開（沒按滿）：外圈從現在的進度縮回去
                releaseProgress = min(1, CGFloat(Date().timeIntervalSince(s) / duration))
                releaseTime = Date()
                startTime = nil
                scheduleResetEnd()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(done ? "今天記好了" : "按住一秒半，記一節")
        .accessibilityHint(done ? "" : hint)
        .accessibilityAddTraits(done ? [] : .isButton)
        .accessibilityAction { complete() }
    }

    private func progress(at date: Date) -> CGFloat {
        if full { return 1 }
        if let s = startTime {
            return min(1, CGFloat(date.timeIntervalSince(s) / duration))
        }
        if let r = releaseTime {
            let k = 1 - min(1, date.timeIntervalSince(r) / resetDuration)
            return releaseProgress * CGFloat(k)
        }
        return 0
    }

    private func scheduleResetEnd() {
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(resetDuration + 0.05))
            guard !Task.isCancelled else { return }
            releaseTime = nil
            full = false
        }
    }

    private func complete() {
        guard !done else { return }
        resetTask?.cancel()
        startTime = nil
        releaseTime = nil
        releaseProgress = 0
        full = true
        onComplete()
        // 沒記成（按鈕還在）就放回去
        scheduleResetEnd()
    }
}
