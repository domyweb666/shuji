import SwiftUI

/// 土裡那顆地瓜的尺寸與外觀。按鈕和記好、請假、放手的樣子共用，換狀態位置不跳。
struct PotatoBody<Label: View>: View {
    var fill: Color
    /// 外圈跑到哪（0 到 1）
    var ring: CGFloat
    var ringColor: Color
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
                PotatoRing(progress: 1)
                    .stroke(ringColor.opacity(0.45), lineWidth: Sz.heroRingWidth)
                    .frame(width: Self.ringSize.width, height: Self.ringSize.height)
                PotatoRing(progress: ring)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: Sz.heroRingWidth * 2, lineCap: .round))
                    .frame(width: Self.ringSize.width, height: Self.ringSize.height)
                Ellipse()
                    .fill(fill)
                    .frame(width: size.width, height: size.height)
                Ellipse()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: size.width * 0.38, height: size.height * 0.22)
                    .offset(x: -size.width * 0.18, y: -size.height * 0.26)
                PotatoMarks()
                    .stroke(Color.black.opacity(0.18), style: StrokeStyle(lineWidth: Sz.heroRingWidth, lineCap: .round))
                    .frame(width: size.width, height: size.height)
            }
            .rotationEffect(tilt)
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

/// 今天的狀態：記好了是產品色實心加滿圈，請假、放手是安靜的淡色
struct PotatoSeal: View {
    enum Style { case done, quiet }

    var icon: String
    var title: String
    var style: Style
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let done = style == .done
        PotatoBody(fill: done ? Theme.accent : Theme.soft, ring: done ? 1 : 0, ringColor: Theme.potatoRing(scheme)) {
            VStack(spacing: Sp.s1) {
                Image(systemName: icon).font(Ty.title2.font)
                Text(title).domyType(Ty.headline)
            }
            .foregroundStyle(done ? Theme.onAccent : Theme.strong)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// 按住土裡那顆地瓜一秒半，外圈跑滿就記一節。放開就縮回去。
/// 這是整個 app 唯一的核心動作，刻意要「按住」而不是「點一下」。按著的時候地瓜慢慢脹大。
struct HoldButton: View {
    /// 只給讀屏
    var hint: String
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
            PotatoBody(fill: pressing ? Theme.strong : Theme.accent, ring: p, ringColor: Theme.potatoRing(scheme)) {
                Text("按住")
                    .domyType(Ty.title1)
                    .tracking(2)
                    .foregroundStyle(Theme.onAccent)
            }
            .scaleEffect(reduceMotion ? 1 : 1 + HoldButton.swell * p)
        }
        .animation(Feel.press, value: pressing)
        .contentShape(Ellipse())
        .gesture(
            LongPressGesture(minimumDuration: duration, maximumDistance: 40)
                .updating($pressing) { value, state, _ in state = value }
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
        .accessibilityLabel("按住一秒半，記一節")
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
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
