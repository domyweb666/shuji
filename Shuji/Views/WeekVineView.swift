import Accessibility
import SwiftUI

/// 週報：一條藤七片葉，土裡的地瓜說一句，要改就按一下（多米 2026-11-25 定，草圖 WeekB）。
struct WeekVineView: View {
    var report: WeekReport
    var close: () -> Void
    /// 測試用的假回覆；正式版永遠是 nil
    var fake: WeekReviewOutput? = nil

    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 地瓜說的那一句；nil 是還在想
    @State private var finding: String? = nil
    @State private var change: WeekChange? = nil
    @State private var changed = false
    @State private var needsConsent = false
    /// 同意送出去之後加一，再問一次
    @State private var round = 0

    private var garden: Theme.Garden { Theme.garden(scheme) }

    var body: some View {
        let ledger = store.state.ledger(today: store.today)
        let leaves = ledger.weekLeaves(end: report.end)
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    sky(leaves, week: ledger.weekNumber(end: report.end))
                    soil
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            // 拉過頭的時候，上面是天、下面是土
            VStack(spacing: 0) {
                Theme.canvas
                garden.soilDeep
            }
            .ignoresSafeArea()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Rd.xxl)
        .presentationBackground(Theme.canvas)
        .tint(Theme.accent)
        .task(id: round) { await load() }
        .sheet(isPresented: $needsConsent, onDismiss: afterConsent) {
            AIConsentSheet(destination: AIClient.shared.destination, agree: agree, decline: { needsConsent = false })
        }
    }

    // MARK: 天

    private func sky(_ leaves: [WeekLeaf], week: Int) -> some View {
        VStack(alignment: .leading, spacing: Sp.s4) {
            header(leaves.filter(\.grown).count, week: week)
                .padding(.horizontal, Sz.screenMargin)
                .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            VStack(spacing: Sp.s1) {
                WeekDayNames(leaves: leaves)
                WeekVine(leaves: leaves)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WeekWords.spoken(leaves))
            .accessibilityAddTraits(.isImage)
        }
        .padding(.top, Sp.s8)
        .background(Theme.canvas)
    }

    private func header(_ n: Int, week: Int) -> some View {
        let big = Text("\(n) 片")
            .domyType(Ty.largeTitle)
            .monospacedDigit()
            .foregroundStyle(Theme.fg)
        let small = Text("第 \(week) 週")
            .domyType(Ty.body)
            .foregroundStyle(Theme.fg2)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Sp.s3) {
                big
                small
            }
            VStack(alignment: .leading, spacing: Sp.s1) {
                big
                small
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("week-vine")
    }

    // MARK: 土

    private var soil: some View {
        VStack(alignment: .leading, spacing: Sp.s5) {
            talk
            answer
            if case .trialResult(let r)? = report.observation {
                TrialResultCard(result: r)
            }
            Spacer(minLength: Sp.s3)
            estimate
        }
        .padding(.horizontal, Sz.screenMargin)
        .padding(.bottom, Sp.s6)
        .frame(maxWidth: Theme.contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [garden.soil, garden.soilDeep], startPoint: .top, endPoint: .bottom))
    }

    /// 地瓜和它說的話。字放很大時上下排
    @ViewBuilder
    private var talk: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Sp.s3) {
                WeekPotato()
                bubble
            }
        } else {
            HStack(spacing: Sp.s3) {
                WeekPotato()
                bubble
            }
        }
    }

    private var bubble: some View {
        Group {
            if let finding {
                Text(finding)
                    .domyType(Ty.headline)
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else {
                ThinkingDots()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Sp.s5)
        .padding(.vertical, Sp.s4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Rd.xl, style: .continuous))
        .accessibilityIdentifier("week-finding")
    }

    /// 想好之後才有按鈕，不會按到一半換掉
    @ViewBuilder
    private var answer: some View {
        if finding != nil {
            if let change, !changed {
                changeCard(change)
            } else {
                if changed {
                    Text("改好了")
                        .domyType(Ty.headline)
                        .foregroundStyle(Theme.fg)
                        .frame(maxWidth: .infinity)
                        .padding(Sp.s4)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Rd.xl, style: .continuous))
                }
                DomyButton("好", variant: .secondary) { close() }
            }
        }
    }

    private func changeCard(_ c: WeekChange) -> some View {
        VStack(alignment: .leading, spacing: Sp.s4) {
            VStack(alignment: .leading, spacing: Sp.s2) {
                Text(c.label)
                    .domyType(Ty.subheadline)
                    .foregroundStyle(Theme.fg2)
                Text(c.text)
                    .domyType(Ty.title1)
                    .foregroundStyle(Theme.fg)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            VStack(spacing: Sp.s2) {
                DomyButton("就這樣改") { apply(c) }
                DomyButton("先不改", variant: .plain, fullWidth: true) { keep() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Sp.s6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Rd.xxl, style: .continuous))
    }

    @ViewBuilder
    private var estimate: some View {
        if let p = store.state.estimateProgress(today: store.today), p.total > 0,
           let d = store.state.estimateDate(today: store.today) {
            let walked = Text("走到第 \(p.done) 天")
            let grown = Text(verbatim: "\(d.month)月\(d.day)日長好")
            VStack(alignment: .leading, spacing: Sp.s3) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Sp.s3) {
                        walked
                        Spacer(minLength: Sp.s3)
                        grown
                    }
                    VStack(alignment: .leading, spacing: Sp.s1) {
                        walked
                        grown
                    }
                }
                .domyType(Ty.headline)
                .monospacedDigit()
                .foregroundStyle(Color.white)
                EstimateBar(value: Double(p.done) / Double(p.total))
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: 動作

    private func load() async {
        guard finding == nil else { return }
        guard let input = store.state.weekReviewInput(end: report.end, today: store.today) else {
            close()
            return
        }
        if let fake {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { settle(fake, input) }
            return
        }
        guard AIClient.shared.isAvailable else {
            settle(nil, input)
            return
        }
        guard AIClient.shared.hasConsented else {
            needsConsent = true
            return
        }
        let out = await WeekReviewAI.ask(input, habitId: store.state.habit?.id)
        if !Task.isCancelled { settle(out, input) }
    }

    private func settle(_ out: WeekReviewOutput?, _ input: WeekReviewInput) {
        let text = out.map { $0.finding.trimmingCharacters(in: .whitespacesAndNewlines) } ?? WeekWords.fallback(input)
        withAnimation(Feel.transition) {
            change = store.state.habit.flatMap { WeekChange(out?.change, habit: $0) }
            finding = text
        }
        AccessibilityNotification.Announcement(text).post()
    }

    private func agree() {
        AIClient.shared.hasConsented = true
        needsConsent = false
        round += 1
    }

    /// 說不用、或把說明拉掉：用程式寫的那一句
    private func afterConsent() {
        guard finding == nil, !AIClient.shared.hasConsented,
              let input = store.state.weekReviewInput(end: report.end, today: store.today) else { return }
        settle(nil, input)
    }

    private func apply(_ c: WeekChange) {
        Haptic.select()
        store.updateHabit(via: .week) { c.field.apply(c.text, to: &$0) }
        withAnimation(Feel.change) { changed = true }
    }

    /// 沒別的要看就關掉；試兩週的結果還在下面就留著
    private func keep() {
        if case .trialResult? = report.observation {
            withAnimation(Feel.change) { change = nil }
        } else {
            close()
        }
    }
}

// MARK: - 藤

/// 一到日，漏掉的那天粗一點
private struct WeekDayNames: View {
    var leaves: [WeekLeaf]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(leaves, id: \.day) { leaf in
                Text(leaf.day.weekName)
                    .domyType(Ty.subheadline)
                    .fontWeight(leaf.kind == .missed ? .bold : .regular)
                    .foregroundStyle(leaf.kind == .missed ? Theme.strong : Theme.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Sz.screenMargin)
        .frame(maxWidth: Theme.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }
}

/// 插畫：土面、藤、七片葉、根。葉子由左到右長出來，0.4 秒
private struct WeekVine: View {
    var leaves: [WeekLeaf]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date? = nil
    @State private var grown = false

    private static let height: CGFloat = 150 // domy-ignore: 插畫尺寸
    private static let duration: TimeInterval = 0.4
    /// 葉子比月曆格放大多少
    private static let leafScale = 1.6

    var body: some View {
        let full = grown || reduceMotion
        TimelineView(.animation(paused: full)) { timeline in
            Canvas { ctx, size in
                draw(&ctx, size: size, p: full ? 1 : progress(timeline.date))
            }
        }
        .frame(height: WeekVine.height)
        .task {
            start = Date()
            try? await Task.sleep(for: .seconds(WeekVine.duration + 0.1))
            grown = true
        }
    }

    private func progress(_ now: Date) -> Double {
        guard let start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / WeekVine.duration))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, p: Double) {
        let garden = Theme.garden(scheme)
        let soilY: Double = 56
        let inner = min(size.width, Theme.contentMaxWidth) - Sz.screenMargin * 2
        let column = Double(inner) / 7
        let left = Double(size.width - inner) / 2
        func x(_ i: Int) -> Double { left + column * (Double(i) + 0.5) }
        func vineY(_ i: Int) -> Double { soilY - 3 + sin(Double(i) * 0.9) * 2 }
        /// 每片葉子自己的進度，一片接一片
        func grow(_ i: Int) -> Double {
            let t = min(1, max(0, (p - Double(i) / 7 * 0.6) / 0.4))
            return 1 - pow(1 - t, 3)
        }

        var soil = Path()
        soil.move(to: CGPoint(x: 0, y: size.height))
        soil.addLine(to: CGPoint(x: 0, y: soilY))
        var sx = 0.0
        while sx <= Double(size.width) + 10 {
            soil.addLine(to: CGPoint(x: sx, y: soilY + sin(sx * 0.035) * 2.2))
            sx += 10
        }
        soil.addLine(to: CGPoint(x: size.width, y: size.height))
        soil.closeSubpath()
        ctx.fill(soil, with: .color(garden.soil))

        for (i, leaf) in leaves.enumerated() where leaf.grown {
            let s = grow(i)
            if s <= 0 { continue }
            var root = Path()
            root.move(to: CGPoint(x: x(i), y: vineY(i)))
            root.addQuadCurve(to: CGPoint(x: x(i) - 4, y: vineY(i) + 68 * s),
                              control: CGPoint(x: x(i) + 8, y: vineY(i) + 34 * s))
            ctx.stroke(root, with: .color(garden.root), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // 藤爬到最後一片長出來的葉子
        if let last = leaves.lastIndex(where: { $0.grown }) {
            var vine = Path()
            vine.move(to: CGPoint(x: left * 0.5, y: soilY - 1))
            for i in 0...last {
                let from = i == 0 ? left * 0.5 : x(i - 1)
                vine.addQuadCurve(to: CGPoint(x: x(i), y: vineY(i)),
                                  control: CGPoint(x: (from + x(i)) / 2, y: vineY(i) - 6))
            }
            if last < 6 {
                vine.addLine(to: CGPoint(x: x(last) + column * 0.5, y: soilY - 2))
            }
            ctx.stroke(vine.trimmedPath(from: 0, to: p), with: .color(garden.vine),
                       style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }

        for (i, leaf) in leaves.enumerated() where leaf.kind != .none {
            let s = grow(i)
            if s <= 0 { continue }
            var g = ctx
            // 從葉柄長出來
            g.translateBy(x: x(i), y: soilY - 8)
            g.scaleBy(x: WeekVine.leafScale * s, y: WeekVine.leafScale * s)
            g.translateBy(x: 0, y: -12)
            mark(&g, leaf.kind, garden)
        }
    }

    /// 跟月曆的葉子同一套座標
    private func mark(_ g: inout GraphicsContext, _ kind: WeekLeaf.Kind, _ garden: Theme.Garden) {
        switch kind {
        case .none:
            break
        case .done, .back:
            g.fill(WeekVine.leafPath, with: .color(garden.leaf))
            var rib = Path()
            rib.move(to: CGPoint(x: 0, y: 11))
            rib.addLine(to: CGPoint(x: 0, y: -4))
            g.stroke(rib, with: .color(garden.leafDark), lineWidth: 1)
            if kind == .back { flower(&g, garden) }
        case .skip:
            g.stroke(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(Theme.accent), lineWidth: 2)
        case .missed:
            g.stroke(WeekVine.leafPath, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
        }
    }

    private func flower(_ g: inout GraphicsContext, _ garden: Theme.Garden) {
        for k in 0..<5 {
            let a = Double(k) / 5 * 2 * Double.pi - Double.pi / 2
            let fx = 8 + cos(a) * 4
            let fy = 6 + sin(a) * 4
            g.fill(Path(ellipseIn: CGRect(x: fx - 3.4, y: fy - 3.4, width: 6.8, height: 6.8)), with: .color(garden.flower))
        }
        g.fill(Path(ellipseIn: CGRect(x: 5.6, y: 3.6, width: 4.8, height: 4.8)), with: .color(garden.flowerCore))
    }

    private static var leafPath: Path {
        var leaf = Path()
        leaf.move(to: CGPoint(x: 0, y: 12))
        leaf.addCurve(to: CGPoint(x: -7, y: -10), control1: CGPoint(x: -12, y: 8), control2: CGPoint(x: -15, y: -7))
        leaf.addCurve(to: CGPoint(x: 0, y: -6), control1: CGPoint(x: -3, y: -11), control2: CGPoint(x: -1, y: -8))
        leaf.addCurve(to: CGPoint(x: 7, y: -10), control1: CGPoint(x: 1, y: -8), control2: CGPoint(x: 3, y: -11))
        leaf.addCurve(to: CGPoint(x: 0, y: 12), control1: CGPoint(x: 15, y: -7), control2: CGPoint(x: 12, y: 8))
        leaf.closeSubpath()
        return leaf
    }
}

/// 有眼睛的地瓜（插畫，座標照草圖 WeekB）
private struct WeekPotato: View {
    @Environment(\.colorScheme) private var scheme

    private static let width: CGFloat = 140 // domy-ignore: 插畫尺寸
    private static let height: CGFloat = 104 // domy-ignore: 插畫尺寸

    var body: some View {
        let garden = Theme.garden(scheme)
        Canvas { ctx, size in
            var g = ctx
            g.translateBy(x: size.width / 2, y: 61)
            g.scaleBy(x: 0.85, y: 0.85)

            var stem = Path()
            stem.move(to: CGPoint(x: 0, y: -44))
            stem.addQuadCurve(to: CGPoint(x: 18, y: -60), control: CGPoint(x: 4, y: -58))
            g.stroke(stem, with: .color(garden.vine), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            var leaf = Path()
            leaf.move(to: CGPoint(x: 18, y: -60))
            leaf.addCurve(to: CGPoint(x: 34, y: -50), control1: CGPoint(x: 30, y: -68), control2: CGPoint(x: 42, y: -58))
            leaf.addCurve(to: CGPoint(x: 18, y: -60), control1: CGPoint(x: 28, y: -44), control2: CGPoint(x: 20, y: -50))
            leaf.closeSubpath()
            g.fill(leaf, with: .color(garden.leaf))

            var skin = g
            skin.rotate(by: .degrees(-8))
            skin.fill(Path(ellipseIn: CGRect(x: -78, y: -45, width: 156, height: 90)), with: .color(Theme.accent))
            skin.fill(Path(ellipseIn: CGRect(x: -56, y: -31, width: 56, height: 18)), with: .color(Color.white.opacity(0.18)))

            g.fill(Path(ellipseIn: CGRect(x: -22.5, y: -4.5, width: 9, height: 9)), with: .color(Theme.onAccent))
            g.fill(Path(ellipseIn: CGRect(x: 17.5, y: -8.5, width: 9, height: 9)), with: .color(Theme.onAccent))
        }
        .frame(width: WeekPotato.width, height: WeekPotato.height)
        .accessibilityHidden(true)
    }
}

/// 還在想：三個點
private struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.4)) { timeline in
            let on = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3
            HStack(spacing: Sp.s2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.fg2)
                        .opacity(reduceMotion || i == on ? 1 : 0.3)
                        .frame(width: Sp.s2, height: Sp.s2)
                }
            }
        }
        .frame(minHeight: Sp.s6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("地瓜在想")
    }
}

/// 土底上的進度條
private struct EstimateBar: View {
    /// 0 到 1
    var value: Double

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.3))
            .frame(height: Sp.s3)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.bakedRim)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                }
            }
            .accessibilityHidden(true)
    }
}
