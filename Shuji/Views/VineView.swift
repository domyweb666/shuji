import SwiftUI
import CoreMotion

/// 地瓜藤：每做一節長一片葉、往下紮一條根；回來那一節開一朵花。
/// 原型是 canvas 2D，這裡用 Canvas + TimelineView 逐幀畫，數字全部照搬。
struct VineView: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = VineModel()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                model.step(now: timeline.date, size: size, reduce: reduceMotion)
                model.draw(in: &context, size: size, garden: Theme.garden(scheme), now: timeline.date, reduce: reduceMotion)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { point in model.tap(at: point) }
        .accessibilityLabel("地瓜藤，共 \(store.state.doneKeys.count) 節")
        .onAppear {
            sync()
            model.startMotion()
        }
        .onDisappear { model.stopMotion() }
        .onChange(of: store.state.logs) { _, _ in sync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.startMotion() } else { model.stopMotion() }
        }
    }

    private func sync() {
        let ds = store.state.doneKeys
        let returns = ds.map { store.state.isReturn($0, doneKeys: ds) }
        model.configure(returns: returns, animateLast: store.vineGrow, reduce: reduceMotion)
        store.vineGrow = false
    }
}

final class VineModel {
    struct Leaf {
        let index: Int
        var a: Double = 0
        var w: Double = 0
        let ret: Bool
    }

    struct Particle {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var life: Double = 0
    }

    struct Grow {
        let t0: Date
        let index: Int
        let ret: Bool
        var spawned = false
    }

    static let spacing = 48.0

    private(set) var leaves: [Leaf] = []
    private var parts: [Particle] = []
    private var grow: Grow?
    private var cam = 0.0
    private var camT = 0.0
    private var camReady = false
    private var pendingGrow = false
    private var tilt = 0.0
    private var lastTime: Date?
    private var frameDt = 1.0 / 60
    private var width = 0.0
    private var height = 0.0
    private let motion = CMMotionManager()

    func configure(returns: [Bool], animateLast: Bool, reduce: Bool) {
        leaves = returns.enumerated().map { Leaf(index: $0.offset, ret: $0.element) }
        parts = []
        if animateLast, let last = leaves.last, !reduce {
            grow = Grow(t0: Date(), index: last.index, ret: last.ret)
            pendingGrow = true
        } else {
            grow = nil
            pendingGrow = false
        }
        camReady = false
    }

    // MARK: 手機傾斜，葉子跟著晃

    func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            self?.tilt = m.gravity.x
        }
    }

    func stopMotion() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
    }

    // MARK: 幾何

    private func soilY() -> Double { max(height * 0.5, height - 150) }

    private func nodePos(_ i: Int) -> (Double, Double) {
        (40 + Double(i) * VineModel.spacing - cam, soilY() - 4 + sin(Double(i) * 0.9) * 5)
    }

    private func seeded(_ i: Int) -> Double {
        let x = sin(Double(i) * 127.1 + 311.7) * 43758.5453
        return x - floor(x)
    }

    private func ease(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    private func spring(_ t: Double) -> Double { t >= 1 ? 1 : 1 - exp(-6 * t) * cos(10 * t) }

    /// 點一片葉子，撥它一下
    func tap(at p: CGPoint) {
        for idx in leaves.indices {
            let (nx, ny) = nodePos(leaves[idx].index)
            if hypot(nx - p.x, ny - 30 - p.y) < 30 {
                leaves[idx].w += (p.x < nx ? -1 : 1) * 7
            }
        }
    }

    // MARK: 每幀

    func step(now: Date, size: CGSize, reduce: Bool) {
        if width != size.width || height != size.height {
            width = size.width
            height = size.height
            let target = Double(leaves.count - 1) * VineModel.spacing + 40 - width * 0.62
            camT = target
        }
        if !camReady {
            let target = Double(leaves.count - 1) * VineModel.spacing + 40 - width * 0.62
            camT = target
            cam = pendingGrow ? target - VineModel.spacing : target
            camReady = true
            pendingGrow = false
        }
        let dt = min(0.05, lastTime.map { now.timeIntervalSince($0) } ?? 0.016)
        lastTime = now
        frameDt = dt
        cam += (camT - cam) * (reduce ? 1 : min(1, dt * 3))
    }

    func draw(in gc: inout GraphicsContext, size: CGSize, garden: Theme.Garden, now: Date, reduce: Bool) {
        let W = size.width
        let H = size.height
        let sy = soilY()
        let dt = frameDt

        // 土
        var soil = Path()
        soil.move(to: CGPoint(x: 0, y: H))
        soil.addLine(to: CGPoint(x: 0, y: sy + 4))
        var sx = 0.0
        while sx <= W + 10 {
            soil.addLine(to: CGPoint(x: sx, y: sy + 3 + sin((sx + cam * 0.6) * 0.05) * 2.2))
            sx += 10
        }
        soil.addLine(to: CGPoint(x: W, y: H))
        soil.closeSubpath()
        gc.fill(soil, with: .color(garden.soil))
        gc.fill(Path(CGRect(x: 0, y: sy + 6, width: W, height: max(0, H - sy))),
                with: .linearGradient(Gradient(colors: [garden.soilDeep.opacity(0), garden.soilDeep]),
                                      startPoint: CGPoint(x: 0, y: sy), endPoint: CGPoint(x: 0, y: H)))
        var grain = Path()
        let span = W + 20
        for i in 0..<90 {
            let raw = seeded(i) * W * 2 - cam * 0.6
            let gx = ((raw.truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span)) - 10
            let gy = sy + 12 + seeded(i + 99) * (H - sy - 16)
            grain.addRect(CGRect(x: gx, y: gy, width: 2, height: 2))
        }
        gc.fill(grain, with: .color(garden.grain))

        let n = leaves.count
        var a = grow.map { now.timeIntervalSince($0.t0) } ?? 9
        if reduce && grow != nil { a = 9 }

        // 根
        for L in leaves {
            let (x, y) = nodePos(L.index)
            if x < -60 || x > W + 60 { continue }
            var p = 1.0
            if let g = grow, L.index == g.index { p = max(0, min(1, (a - 0.6) / 0.8)) }
            if p <= 0 { continue }
            let len = 34 + seeded(L.index) * 40
            var root = Path()
            root.move(to: CGPoint(x: x, y: y + 2))
            let segs = 8.0
            var s = 1.0
            while s <= segs * p {
                let t = s / segs
                root.addLine(to: CGPoint(x: x + sin(t * 5 + Double(L.index)) * 4 * t + (seeded(L.index + 3) - 0.5) * 14 * t,
                                         y: y + 2 + len * t))
                s += 1
            }
            gc.stroke(root, with: .color(garden.root), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            var side = Path()
            side.move(to: CGPoint(x: x + 1, y: y + len * 0.4 * p + 2))
            side.addLine(to: CGPoint(x: x + (seeded(L.index + 7) - 0.5) * 26 * p, y: y + len * 0.6 * p + 6))
            gc.stroke(side, with: .color(garden.root), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }

        // 藤
        if n > 0 {
            let (x0, y0) = nodePos(0)
            var vine = Path()
            vine.move(to: CGPoint(x: x0 - 40, y: y0 + 3))
            for i in 0..<n {
                var (x, y) = nodePos(i)
                if let g = grow, i == g.index {
                    let p = ease(min(1, a / 0.6))
                    let (px, py) = i > 0 ? nodePos(i - 1) : (x - 40, y)
                    x = px + (x - px) * p
                    y = py + (y - py) * p
                }
                let (px, py) = i > 0 ? nodePos(i - 1) : (x0 - 40, y0 + 3)
                vine.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: (px + x) / 2, y: min(py, y) - 6))
            }
            gc.stroke(vine, with: .color(garden.vine), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

            // 尾端捲鬚
            let (tx, ty) = nodePos(n - 1)
            let tp = grow != nil ? ease(min(1, a / 0.6)) : 1
            if tp >= 1 {
                var curl = Path()
                curl.move(to: CGPoint(x: tx, y: ty))
                curl.addQuadCurve(to: CGPoint(x: tx + 22, y: ty - 18), control: CGPoint(x: tx + 18, y: ty - 8))
                curl.addQuadCurve(to: CGPoint(x: tx + 17, y: ty - 24), control: CGPoint(x: tx + 24, y: ty - 26))
                gc.stroke(curl, with: .color(garden.vine), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        // 葉、花
        for idx in leaves.indices {
            let (x, y) = nodePos(leaves[idx].index)
            if x < -60 || x > W + 60 { continue }
            let i = leaves[idx].index
            let base = i % 2 == 1 ? 0.3 : -0.3
            let target = tilt * 0.6
            leaves[idx].w += (-(leaves[idx].a - target) * 38 - leaves[idx].w * 3.2) * dt
            leaves[idx].a += leaves[idx].w * dt
            let L = leaves[idx]
            var s = 1.0
            if let g = grow, i == g.index { s = a < 0.3 ? 0 : spring((a - 0.3) / 0.6) }
            if s <= 0 { continue }

            var g = gc
            g.translateBy(x: x, y: y)
            g.rotate(by: .radians(base + L.a))
            var stem = Path()
            stem.move(to: .zero)
            stem.addLine(to: CGPoint(x: 0, y: -14 * s))
            g.stroke(stem, with: .color(garden.vine), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            g.translateBy(x: 0, y: -12 * s)
            let sc = s * (0.9 + seeded(i) * 0.25)
            g.fill(leafPath(sc), with: .color(garden.leaf))
            var rib = Path()
            rib.move(to: CGPoint(x: 0, y: -1))
            rib.addLine(to: CGPoint(x: 0, y: -23 * sc))
            g.stroke(rib, with: .color(garden.leafDark), lineWidth: 1)

            if L.ret {
                var fs = 1.0
                if let gr = grow, i == gr.index { fs = a < 0.8 ? 0 : spring((a - 0.8) / 0.5) }
                if fs > 0 {
                    drawFlower(in: &gc, x: x + (i % 2 == 1 ? -14 : 14), y: y - 10, s: fs * 1.05,
                               rot: (1 - fs) * 0.8 + L.a * 0.5, garden: garden)
                }
            }
        }

        // 土粒
        if var g = grow, !g.spawned, a > 0.65, !reduce {
            g.spawned = true
            grow = g
            let (x, y) = nodePos(g.index)
            for _ in 0..<8 {
                parts.append(Particle(x: x + (Double.random(in: 0..<1) - 0.5) * 14, y: y + 4,
                                      vx: (Double.random(in: 0..<1) - 0.5) * 80,
                                      vy: -60 - Double.random(in: 0..<1) * 90))
            }
        }
        var alive: [Particle] = []
        for var p in parts {
            p.life += dt
            p.vy += 420 * dt
            p.x += p.vx * dt
            p.y += p.vy * dt
            var g = gc
            g.opacity = max(0, 1 - p.life / 0.7)
            g.fill(Path(CGRect(x: p.x, y: p.y, width: 3, height: 3)), with: .color(garden.soilDeep))
            if p.life < 0.7 { alive.append(p) }
        }
        parts = alive

        // 還沒種：一小芽
        if n == 0 {
            var sprout = Path()
            sprout.move(to: CGPoint(x: W * 0.5, y: sy + 2))
            sprout.addQuadCurve(to: CGPoint(x: W * 0.5 + 6, y: sy - 16), control: CGPoint(x: W * 0.5 - 2, y: sy - 10))
            gc.stroke(sprout, with: .color(garden.vine), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            var g = gc
            g.translateBy(x: W * 0.5 + 6, y: sy - 16)
            g.rotate(by: .radians(0.5))
            g.fill(leafPath(0.45), with: .color(garden.leaf))
        }

        if grow != nil && a > 2.2 { grow = nil }
    }

    private func leafPath(_ s: Double) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: -9 * s, y: -27 * s), control1: CGPoint(x: -14 * s, y: -4 * s), control2: CGPoint(x: -20 * s, y: -20 * s))
        p.addCurve(to: CGPoint(x: 0, y: -24 * s), control1: CGPoint(x: -4 * s, y: -30 * s), control2: CGPoint(x: -1 * s, y: -28 * s))
        p.addCurve(to: CGPoint(x: 9 * s, y: -27 * s), control1: CGPoint(x: 1 * s, y: -28 * s), control2: CGPoint(x: 4 * s, y: -30 * s))
        p.addCurve(to: .zero, control1: CGPoint(x: 20 * s, y: -20 * s), control2: CGPoint(x: 14 * s, y: -4 * s))
        p.closeSubpath()
        return p
    }

    private func drawFlower(in gc: inout GraphicsContext, x: Double, y: Double, s: Double, rot: Double, garden: Theme.Garden) {
        var g = gc
        g.translateBy(x: x, y: y)
        g.rotate(by: .radians(rot))
        g.scaleBy(x: s, y: s)
        for k in 0..<5 {
            var petal = g
            petal.rotate(by: .radians(Double(k) * Double.pi * 2 / 5))
            petal.translateBy(x: 0, y: -6)
            petal.rotate(by: .radians(Double(k) * Double.pi * 2 / 5))
            petal.fill(Path(ellipseIn: CGRect(x: -5.2, y: -6.8, width: 10.4, height: 13.6)), with: .color(garden.flower))
        }
        g.fill(Path(ellipseIn: CGRect(x: -6.5, y: -6.5, width: 13, height: 13)), with: .color(garden.flower))
        g.fill(Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6)), with: .color(garden.flowerCore))
    }
}
