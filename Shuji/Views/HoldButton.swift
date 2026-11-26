import SwiftUI

/// 土裡那顆地瓜的尺寸與外觀。按鈕和記好、跳過、放手的樣子共用，換狀態位置不跳。
/// 造型是 B（多米 2026-11-26 換掉 D）：橫躺、長條彎身、一根細根往上，記好了縱切攤開冒煙。
/// 插畫座標照畫布（寬 380 高 400），地瓜身體中心在 (194, 222)，縮成 0.84 倍放進 264×196 的位子。
struct PotatoBody<Label: View>: View {
    var fill: Color
    /// 外圈跑到哪（0 到 1）
    var ring: CGFloat
    var ringColor: Color
    /// 記好了：1 是剝開，0 是原本的樣子
    var open: CGFloat = 0
    /// 剝開的那塊上面要寫字：紋路不畫
    var written = false
    @ViewBuilder var label: Label
    @Environment(\.colorScheme) private var scheme

    /// 地瓜本體、外圈、整塊佔的大小（插畫，不走代號）
    static var bodySize: CGSize { CGSize(width: 222, height: 89) }
    static var ringSize: CGSize { CGSize(width: 252, height: 136) }
    static var frameSize: CGSize { CGSize(width: 264, height: 196) }
    /// 畫布比佔的位子高，上面多出來的給煙和細根
    private static var drawSize: CGSize { CGSize(width: 264, height: 260) }

    var body: some View {
        let mud = Theme.garden(scheme).soilDeep
        ZStack {
            Group {
                PotatoRing(progress: 1)
                    .stroke(ringColor.opacity(0.45), lineWidth: Sz.heroRingWidth)
                PotatoRing(progress: ring)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: Sz.heroRingWidth * 2, lineCap: .round))
            }
            .frame(width: Self.ringSize.width, height: Self.ringSize.height)
            .opacity(1 - open)
            PotatoArt(open: true, fill: fill, rim: ringColor, mud: mud, written: written)
                .frame(width: Self.drawSize.width, height: Self.drawSize.height)
                .opacity(open)
            PotatoArt(open: false, fill: fill, rim: ringColor, mud: mud, written: written)
                .frame(width: Self.drawSize.width, height: Self.drawSize.height)
                .opacity(1 - open)
            label
        }
        .frame(width: Self.frameSize.width, height: Self.frameSize.height)
    }
}

/// B 的地瓜。open：縱切攤開、冒煙。竹籃、挖出來、付費頁的小地瓜（PotatoView）也用這個畫
struct PotatoArt: View {
    var open: Bool
    var fill: Color
    var rim: Color
    /// 留著給呼叫的地方傳，B 沒有泥
    var mud: Color
    var written: Bool
    /// 畫布縮放：土裡那顆是 0.84；nil 就照位子塞滿（給小地瓜用）
    var scale: CGFloat? = 0.84

    /// 地瓜身體中心（固定縮放時對準位子中心）
    static let center = CGPoint(x: 194, y: 222)
    /// 整顆含細根與鬚的範圍（畫布座標），塞滿時用
    static let whole = CGRect(x: 60, y: 104, width: 274, height: 182)

    /// 畫布座標換到位子裡：回傳縮放和畫布中心要對到的點
    static func fit(_ size: CGSize, scale: CGFloat?) -> (s: CGFloat, anchor: CGPoint) {
        if let scale { return (scale, center) }
        let s = min(size.width / whole.width, size.height / whole.height)
        return (s, CGPoint(x: whole.midX, y: whole.midY))
    }

    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            let (s, a) = Self.fit(size, scale: scale)
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.scaleBy(x: s, y: s)
            g.translateBy(x: -a.x, y: -a.y)
            if open { drawOpen(&g) } else { drawWhole(&g) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 每一條是 起點、控制點、終點
    private func quads(_ list: [[CGFloat]]) -> Path {
        var p = Path()
        for q in list {
            p.move(to: CGPoint(x: q[0], y: q[1]))
            p.addQuadCurve(to: CGPoint(x: q[4], y: q[5]), control: CGPoint(x: q[2], y: q[3]))
        }
        return p
    }

    private func drawWhole(_ g: inout GraphicsContext) {
        // 往上的那根細根，畫在身體後面
        var root = Path()
        root.move(to: CGPoint(x: 116, y: 182))
        root.addCurve(to: CGPoint(x: 150, y: 106), control1: CGPoint(x: 126, y: 150), control2: CGPoint(x: 152, y: 136))
        g.stroke(root, with: .color(rim.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        g.fill(BShape.body, with: .color(fill))
        g.fill(BShape.shade, with: .color(.black.opacity(0.2)))
        var shine = Path()
        shine.move(to: CGPoint(x: 112, y: 184))
        shine.addCurve(to: CGPoint(x: 236, y: 186), control1: CGPoint(x: 140, y: 166), control2: CGPoint(x: 200, y: 164))
        g.stroke(shine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        let hairs = quads([[146, 252, 142, 266, 134, 280], [224, 262, 228, 274, 236, 284], [276, 220, 286, 212, 298, 210]])
        g.stroke(hairs, with: .color(rim.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }

    private func drawOpen(_ g: inout GraphicsContext) {
        var steam = Path()
        for x in [158.0, 196.0, 234.0] {
            let top = x == 196 ? 150.0 : 156.0
            steam.move(to: CGPoint(x: x, y: top))
            steam.addQuadCurve(to: CGPoint(x: x, y: top - 22), control: CGPoint(x: x - 10, y: top - 11))
            steam.addQuadCurve(to: CGPoint(x: x, y: top - 44), control: CGPoint(x: x + 10, y: top - 33))
        }
        g.stroke(steam, with: .color(rim), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        g.fill(BShape.boat, with: .color(fill))
        g.fill(BShape.boat, with: .color(.black.opacity(0.2)))
        g.fill(BShape.cream, with: .color(Theme.bakedRim))
        g.fill(BShape.flesh, with: .color(Theme.bakedFlesh))
        g.fill(BShape.core, with: .color(Theme.bakedCore))
        if !written {
            let lines = quads([[162, 218, 176, 224, 190, 220], [196, 226, 210, 232, 226, 228], [178, 236, 190, 240, 202, 237]])
            g.stroke(lines, with: .color(Theme.bakedLine.opacity(0.6)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

/// 有眼睛的 B：回來卡、對話、這週的田、田的「還太少」共用。照位子塞滿置中，位子由呼叫的地方給
/// dots：想的時候三個點的透明度；nil 畫兩隻眼睛。眼睛顏色跟著壓在產品色上的字色走，深色模式才看得到
struct PotatoFace: View {
    var dots: [Double]? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            PotatoArt(open: false, fill: Theme.accent, rim: Theme.potatoRing(scheme),
                      mud: Theme.garden(scheme).soilDeep, written: false, scale: nil)
            Canvas { ctx, size in
                let (s, a) = PotatoArt.fit(size, scale: nil)
                func dot(_ x: CGFloat, _ y: CGFloat, _ opacity: Double) {
                    let c = CGPoint(x: size.width / 2 + (x - a.x) * s, y: size.height / 2 + (y - a.y) * s)
                    let r = 9 * s
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.onAccent.opacity(opacity)))
                }
                if let dots {
                    for (i, o) in dots.prefix(3).enumerated() { dot(150 + CGFloat(i) * 32, 220, o) }
                } else {
                    dot(158, 218, 1)
                    dot(204, 216, 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// B 的外形（畫布座標）
private enum BShape {
    /// 起點，之後每三點一段曲線
    static func curves(_ p: [(CGFloat, CGFloat)], close: Bool = true) -> Path {
        var path = Path()
        func pt(_ i: Int) -> CGPoint { CGPoint(x: p[i].0, y: p[i].1) }
        path.move(to: pt(0))
        var i = 1
        while i + 2 < p.count {
            path.addCurve(to: pt(i + 2), control1: pt(i), control2: pt(i + 1))
            i += 3
        }
        if close { path.closeSubpath() }
        return path
    }

    /// 整顆：左邊尖頭，上緣拱起，右邊拖一條往下彎的尾巴
    static let body = curves([(66, 206), (88, 164), (146, 154), (200, 168), (254, 182), (300, 222), (326, 254),
                              (296, 262), (250, 270), (198, 262), (140, 256), (88, 240), (66, 206)])
    /// 下緣的陰影
    static let shade = curves([(326, 254), (296, 262), (250, 270), (198, 262), (140, 256), (88, 240), (66, 206),
                               (100, 232), (150, 242), (200, 246), (250, 250), (296, 246), (326, 254)])
    /// 縱切攤開的外皮：兩頭尖的船形
    static let boat = curves([(60, 210), (94, 170), (150, 160), (198, 168), (254, 178), (304, 222), (330, 256),
                              (294, 266), (248, 276), (196, 270), (130, 264), (80, 240), (60, 210)])
    private static func shrink(_ p: Path, _ sx: CGFloat, _ sy: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> Path {
        let c = CGPoint(x: 196, y: 222)
        let t = CGAffineTransform(translationX: c.x + dx, y: c.y + dy).scaledBy(x: sx, y: sy).translatedBy(x: -c.x, y: -c.y)
        return p.applying(t)
    }
    /// 皮裡面一圈淡色
    static let cream = shrink(boat, 0.93, 0.8)
    /// 烤好的肉
    static let flesh = shrink(boat, 0.86, 0.66)
    /// 黃色肉心，「你回來了」寫在這裡
    static let core = shrink(boat, 0.62, 0.44, dx: -6, dy: 4)
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

/// 按住土裡那顆地瓜一秒半，外圈跑滿就記一節。放開就縮回去。
/// 這是整個 app 唯一的核心動作，刻意要「按住」而不是「點一下」。按著的時候地瓜慢慢脹大。
struct HoldButton: View {
    /// 只給讀屏
    var hint: String
    /// 今天記好了：同一顆地瓜烤好剝開，按了沒反應。用同一個 view，變形才接得起來
    var done = false
    /// 今天是回來的那一節：剝開的地方寫「你回來了」，整天都在
    var back = false
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
                       ringColor: Theme.potatoRing(scheme), open: done ? 1 : 0, written: back) {
                ZStack {
                    Text("按住")
                        .domyType(Ty.title1)
                        .tracking(2)
                        .foregroundStyle(Theme.onAccent)
                        .opacity(done ? 0 : 1)
                    Text("你回來了")
                        .domyType(Ty.title3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.bakedInk)
                        .frame(maxWidth: PotatoBody<EmptyView>.bodySize.width * 0.8)
                        // 放在黃色肉心正中間（B 的肉心比身體中心偏左下一點）
                        .offset(x: -3, y: 3) // domy-ignore: 插畫位置
                        .opacity(done && back ? 1 : 0)
                }
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
        .accessibilityLabel(done ? (back ? "你回來了，今天記好了" : "今天記好了") : "按住一秒半，記一節")
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
