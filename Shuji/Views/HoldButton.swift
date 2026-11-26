import SwiftUI

/// 土裡那顆地瓜的尺寸與外觀。按鈕和記好、跳過、放手的樣子共用，換狀態位置不跳。
/// 造型是 Claude Design 的 D（QC-0011 多米選的）：直立、有鬚根和泥，記好了上半的皮剝開。
/// 插畫座標照畫布（寬 380 高 400），地瓜中心在 (190, 221)，縮成 0.72 倍放進 264×196 的位子。
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
    static var bodySize: CGSize { CGSize(width: 121, height: 186) }
    static var ringSize: CGSize { CGSize(width: 144, height: 193) }
    static var frameSize: CGSize { CGSize(width: 264, height: 196) }
    /// 畫布比佔的位子高，上面多出來的給煙
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

/// D 的地瓜。open：上半的皮剝開、冒煙。竹籃、挖出來、付費頁的小地瓜（PotatoView）也用這個畫
struct PotatoArt: View {
    var open: Bool
    var fill: Color
    var rim: Color
    var mud: Color
    var written: Bool
    /// 畫布縮放：土裡那顆是 0.72；nil 就照高度塞滿（給小地瓜用）
    var scale: CGFloat? = 0.72

    /// 整顆含鬚根和泥的高度（畫布座標），照高度塞滿時用
    static let wholeHeight: CGFloat = 272

    var body: some View {
        Canvas { ctx, size in
            var g = ctx
            let s = scale ?? size.height / Self.wholeHeight
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.scaleBy(x: s, y: s)
            g.translateBy(x: -190, y: -221)
            if open { drawOpen(&g) } else { drawWhole(&g) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func strokeLines(_ g: inout GraphicsContext, _ pts: [(CGFloat, CGFloat, CGFloat, CGFloat)], _ c: Color, _ w: CGFloat) {
        var p = Path()
        for (x1, y1, x2, y2) in pts {
            p.move(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
        }
        g.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round))
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
        g.fill(DShape.body, with: .color(fill))
        g.fill(DShape.shade, with: .color(.black.opacity(0.2)))
        var shine = Path()
        shine.move(to: CGPoint(x: 134, y: 172))
        shine.addCurve(to: CGPoint(x: 176, y: 132), control1: CGPoint(x: 142, y: 152), control2: CGPoint(x: 158, y: 140))
        g.stroke(shine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        let hairs = quads([[108, 196, 86, 200, 72, 216], [112, 226, 94, 236, 88, 254],
                           [270, 188, 292, 188, 310, 202], [258, 238, 278, 246, 286, 262]])
        g.stroke(hairs, with: .color(rim.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        strokeLines(&g, [(134, 164, 156, 164), (224, 156, 242, 156), (146, 262, 166, 262), (208, 276, 230, 276)],
                    .black.opacity(0.22), 3)
        g.fill(Path(ellipseIn: CGRect(x: 134, y: 278, width: 32, height: 16)), with: .color(mud))
        g.fill(Path(ellipseIn: CGRect(x: 224, y: 140, width: 24, height: 12)), with: .color(mud))
    }

    private func drawOpen(_ g: inout GraphicsContext) {
        var steam = Path()
        for x in [150.0, 194.0, 238.0] {
            let top = x == 194 ? 84.0 : 92.0
            steam.move(to: CGPoint(x: x, y: top))
            steam.addQuadCurve(to: CGPoint(x: x, y: top - 26), control: CGPoint(x: x - 12, y: top - 13))
            steam.addQuadCurve(to: CGPoint(x: x, y: top - 52), control: CGPoint(x: x + 12, y: top - 39))
        }
        g.stroke(steam, with: .color(rim), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        g.fill(DShape.flesh, with: .color(Theme.bakedFlesh))
        g.fill(DShape.core, with: .color(Theme.bakedCore))
        if !written {
            let lines = quads([[168, 176, 178, 182, 190, 178], [194, 206, 206, 212, 218, 207], [160, 218, 170, 223, 178, 220]])
            g.stroke(lines, with: .color(Theme.bakedLine.opacity(0.6)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        g.fill(DShape.flaps, with: .color(fill))
        g.fill(DShape.flaps, with: .color(.black.opacity(0.2)))
        g.fill(DShape.bottom, with: .color(fill))
        g.stroke(DShape.edge, with: .color(Theme.bakedRim), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        strokeLines(&g, [(160, 284, 178, 284), (206, 290, 222, 290)], .black.opacity(0.22), 3)
    }
}

/// 有眼睛的 D：回來卡、對話、這週的田、田的「還太少」共用。照高度塞滿置中，位子由呼叫的地方給
/// dots：想的時候三個點的透明度；nil 畫兩隻眼睛。眼睛顏色跟著壓在產品色上的字色走，深色模式才看得到
struct PotatoFace: View {
    var dots: [Double]? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            PotatoArt(open: false, fill: Theme.accent, rim: Theme.potatoRing(scheme),
                      mud: Theme.garden(scheme).soilDeep, written: false, scale: nil)
            Canvas { ctx, size in
                let s = size.height / PotatoArt.wholeHeight
                func dot(_ x: CGFloat, _ y: CGFloat, _ opacity: Double) {
                    let c = CGPoint(x: size.width / 2 + (x - 190) * s, y: size.height / 2 + (y - 221) * s)
                    let r = 9 * s
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.onAccent.opacity(opacity)))
                }
                if let dots {
                    for (i, o) in dots.prefix(3).enumerated() { dot(156 + CGFloat(i) * 34, 212, o) }
                } else {
                    dot(168, 208, 1)
                    dot(214, 202, 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// D 的外形（畫布座標）
private enum DShape {
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

    static let body = curves([(196, 92), (214, 108), (258, 122), (272, 166), (288, 218), (262, 262), (224, 290),
                              (208, 302), (200, 322), (190, 350), (180, 322), (166, 304), (150, 290),
                              (112, 260), (92, 214), (108, 166), (122, 124), (176, 110), (196, 92)])
    static let shade = curves([(272, 166), (288, 218), (262, 262), (224, 290), (208, 302), (200, 322), (190, 350),
                               (186, 330), (196, 300), (214, 276), (246, 236), (258, 206), (256, 140),
                               (264, 148), (270, 156), (272, 166)])
    /// 剝開的鋸齒邊，左到右
    static let jag: [(CGFloat, CGFloat)] = [(106, 214), (120, 236), (134, 222), (148, 240), (164, 258), (178, 230),
                                            (194, 246), (210, 260), (226, 230), (240, 240), (254, 248), (262, 226), (274, 212)]
    static let edge = curves(jag, close: false)
    private static let bottomTail: [(CGFloat, CGFloat)] = [(272, 250), (252, 270), (224, 290), (208, 302), (200, 322), (190, 350),
                                                           (180, 322), (166, 304), (150, 290), (122, 268), (106, 244), (106, 214)]
    static let bottom = curves(jag + bottomTail)
    static let flaps: Path = {
        var p = curves([(106, 216), (76, 226), (66, 256), (78, 278), (88, 258), (104, 250), (114, 250)])
        p.addPath(curves([(272, 214), (304, 226), (312, 256), (302, 278), (292, 258), (276, 250), (264, 250)]))
        return p
    }()
    static let flesh: Path = {
        var p = curves([(194, 96), (214, 110), (254, 126), (266, 168), (274, 200), (268, 226), (256, 248)], close: false)
        p.addLine(to: CGPoint(x: 122, y: 248))
        p.addCurve(to: CGPoint(x: 112, y: 168), control1: CGPoint(x: 108, y: 222), control2: CGPoint(x: 104, y: 196))
        p.addCurve(to: CGPoint(x: 194, y: 96), control1: CGPoint(x: 124, y: 126), control2: CGPoint(x: 176, y: 112))
        p.closeSubpath()
        return p
    }()
    static let core: Path = {
        var p = curves([(190, 122), (208, 134), (232, 150), (238, 180), (242, 204), (238, 226), (230, 244)], close: false)
        p.addLine(to: CGPoint(x: 150, y: 244))
        p.addCurve(to: CGPoint(x: 142, y: 180), control1: CGPoint(x: 140, y: 222), control2: CGPoint(x: 136, y: 202))
        p.addCurve(to: CGPoint(x: 190, y: 122), control1: CGPoint(x: 150, y: 150), control2: CGPoint(x: 176, y: 136))
        p.closeSubpath()
        return p
    }()
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
