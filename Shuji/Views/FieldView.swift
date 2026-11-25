import SwiftUI

/// 田：月曆｜分析。分析是問句卡（2026-11-25 多米選田 B）：問題、答案、一張圖，資料不夠就不出那張。
/// 開始四問、長好了嗎不在這裡：時間到了打開 app 自動問（AutoAsk）。竹籃和排隊收在右上角。
struct FieldView: View {
    enum Side: String, CaseIterable { case month = "月曆", charts = "分析" }

    @Environment(Store.self) private var store
    @State private var side = Side.month
    /// 往前幾個月
    @State private var back = 0
    @State private var showAudit = false
    @State private var showPaywall = false
    @State private var picked: DayPick? = nil

    /// 月曆點的那一天
    struct DayPick: Identifiable {
        let day: DayKey
        var id: String { day.string }
    }

    private let purchases = Purchases.shared

    private var t: DayKey { store.today }

    var body: some View {
        DomyScreen(title: "田") {
            HStack(spacing: Sp.s2) {
                ForEach(Side.allCases, id: \.self) { s in sideButton(s) }
                Button { store.route = [.basket] } label: {
                    Image(systemName: "basket")
                        .font(Ty.headline.font)
                        .foregroundStyle(Theme.fg)
                        .frame(width: Sz.iconButton, height: Sz.iconButton)
                        .background(Theme.surface, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(DomyPressStyle())
                .accessibilityLabel("竹籃與排隊")
            }
        } content: {
            switch side {
            case .month: monthSide
            case .charts: chartSide
            }
        }
        .sheet(item: $picked) { pick in DaySheet(day: pick.day) }
        .sheet(isPresented: $showAudit) { AuditSheet() }
        .sheet(isPresented: $showPaywall) { PaywallSheet() }
    }

    private func sideButton(_ s: Side) -> some View {
        let on = s == side
        return Button {
            Haptic.select()
            withAnimation(Feel.change) { side = s }
        } label: {
            Text(s.rawValue)
                .domyType(Ty.callout)
                .fontWeight(on ? .semibold : .regular)
                .foregroundStyle(on ? Theme.strong : Theme.fg)
                .padding(.horizontal, Sp.s4)
                .frame(height: Sz.touch)
                .background(on ? Theme.soft : Theme.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(DomyPressStyle())
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: 月曆

    @ViewBuilder
    private var monthSide: some View {
        if let m = store.state.monthReport(today: t, back: back) {
            Card {
                VStack(spacing: Sp.s3) {
                    HStack {
                        monthArrow("chevron.left", "上個月", enabled: store.state.monthReport(today: t, back: back + 1) != nil) { back += 1 }
                        Spacer(minLength: 0)
                        Text(verbatim: "\(m.year)年\(m.month)月")
                            .domyType(Ty.headline)
                            .foregroundStyle(Theme.fg)
                        Spacer(minLength: 0)
                        monthArrow("chevron.right", "下個月", enabled: back > 0) { back -= 1 }
                    }
                    MonthGrid(month: m, today: t, planted: store.state.habit?.planted ?? t) { d in picked = DayPick(day: d) }
                }
                .padding(Sp.s4)
            }
            HStack(spacing: Sp.s3) {
                number(m.done, "記了幾天")
                number(m.back, "回來幾次")
                number(m.leave, "跳過幾天")
            }
        }
    }

    private func monthArrow(_ icon: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Feel.change) { action() }
        } label: {
            Image(systemName: icon)
                .font(Ty.headline.font)
                .foregroundStyle(enabled ? Theme.strong : Theme.disabled)
                .frame(width: Sz.touch, height: Sz.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(DomyPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func number(_ n: Int, _ label: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Sp.s1 / 2) {
                Text("\(n)")
                    .domyType(Ty.title1)
                    .monospacedDigit()
                    .foregroundStyle(Theme.fg)
                    .contentTransition(.numericText())
                Text(label)
                    .domyType(Ty.footnote)
                    .foregroundStyle(Theme.fg2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Sp.s4)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 分析

    @ViewBuilder
    private var chartSide: some View {
        let cards = store.state.fieldCards(today: t)
        if let few = cards.few { fewCard(few) }
        if let w = cards.week {
            questionCard(Copy.t(.f1q), w.answer) { WeekBarsView(card: w) }
        }
        if let g = cards.gap {
            questionCard(Copy.t(.f2q), g.answer) {
                VStack(spacing: Sp.s3) {
                    RatioBar(name: Copy.groupName("weekday"), count: g.weekday)
                    RatioBar(name: Copy.groupName("weekend"), count: g.weekend)
                }
            }
        }
        if let e = cards.ease {
            questionCard(Copy.t(.f3q), e.answer) { ChartView(weekly: e.weekly) }
        }
        if let c = cards.time {
            questionCard(Copy.t(.f5q), c.answer) { TimeDots(time: c.time) }
        }
        if let s = cards.skips {
            questionCard(Copy.t(.f4q), s.answer) {
                Text(s.list)
                    .domyType(Ty.body)
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if AIClient.shared.isAvailable && store.state.auditReady(today: t) {
            DomySection {
                RowButton(text: "做這一季的稽核", value: purchases.isFull ? nil : "完整版", tone: .action) {
                    if purchases.isFull { showAudit = true } else { showPaywall = true }
                }
            }
        }
    }

    /// 第一行問題，第二行答案，下面一張圖或原始天數
    private func questionCard<Content: View>(_ question: String, _ answer: String, @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Sp.s4) {
                VStack(alignment: .leading, spacing: Sp.s1) {
                    Text(question)
                        .domyType(Ty.subheadline)
                        .foregroundStyle(Theme.fg2)
                    Text(answer)
                        .domyType(Ty.title2)
                        .foregroundStyle(Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Sp.s5)
        }
    }

    private func fewCard(_ few: FewCard) -> some View {
        Card {
            VStack(spacing: Sp.s5) {
                TalkPotato(width: FieldView.fewPotato)
                Text(few.title)
                    .domyType(Ty.title3)
                    .foregroundStyle(Theme.fg)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = few.progress {
                    FillBar(value: max(p, 0.03), color: Theme.leafDynamic, height: Sp.s2)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Sp.s5)
            .padding(.vertical, Sp.s8)
        }
    }

    private static let fewPotato: CGFloat = 120 // domy-ignore: 插畫尺寸
}

/// 月曆：葉子是記了，帶花是回來，空圈是跳過，漏掉的留白
struct MonthGrid: View {
    var month: MonthReport
    var today: DayKey
    var planted: DayKey
    var pick: (DayKey) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Sp.s2) {
            ForEach(0..<7, id: \.self) { i in
                Text(DayKey.weekNames[i])
                    .domyType(Ty.footnote)
                    .foregroundStyle(Theme.fg2)
                    .accessibilityHidden(true)
            }
            ForEach(0..<month.lead, id: \.self) { i in
                Color.clear.frame(height: Sz.touch).id("lead-\(i)")
            }
            ForEach(month.days, id: \.day) { d in cell(d) }
        }
    }

    /// 種下那天到今天可以點
    @ViewBuilder
    private func cell(_ d: MonthDay) -> some View {
        if d.day >= planted && d.day <= today {
            Button { pick(d.day) } label: { face(d) }
                .buttonStyle(DomyPressStyle())
                .accessibilityLabel("\(d.day.long)\(word(d.kind))")
        } else {
            face(d)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(d.day.long)\(word(d.kind))")
        }
    }

    private func face(_ d: MonthDay) -> some View {
        let isToday = d.day == today
        return VStack(spacing: Sp.s1 / 2) {
            Text("\(d.day.day)")
                .domyType(Ty.footnote)
                .monospacedDigit()
                .foregroundStyle(d.day > today ? Theme.fg3 : Theme.fg)
            LeafMark(kind: d.kind)
                .frame(width: Sp.s6, height: Sp.s6)
        }
        .frame(maxWidth: .infinity, minHeight: Sz.touch)
        .padding(.vertical, Sp.s1)
        .background(isToday ? Theme.soft : Color.clear, in: RoundedRectangle(cornerRadius: Rd.md, style: .continuous))
        .contentShape(Rectangle())
    }

    private func word(_ k: MonthDay.Kind) -> String {
        switch k {
        case .none: return ""
        case .done: return "，記了"
        case .back: return "，回來"
        case .leave: return "，跳過"
        }
    }
}

/// 月曆格裡的小插畫（座標照藤上的葉子縮小）
private struct LeafMark: View {
    var kind: MonthDay.Kind
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let garden = Theme.garden(scheme)
        Canvas { ctx, size in
            var g = ctx
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.scaleBy(x: size.width / 28, y: size.height / 28)
            if kind == .done || kind == .back {
                var leaf = Path()
                leaf.move(to: CGPoint(x: 0, y: 12))
                leaf.addCurve(to: CGPoint(x: -7, y: -10), control1: CGPoint(x: -12, y: 8), control2: CGPoint(x: -15, y: -7))
                leaf.addCurve(to: CGPoint(x: 0, y: -6), control1: CGPoint(x: -3, y: -11), control2: CGPoint(x: -1, y: -8))
                leaf.addCurve(to: CGPoint(x: 7, y: -10), control1: CGPoint(x: 1, y: -8), control2: CGPoint(x: 3, y: -11))
                leaf.addCurve(to: CGPoint(x: 0, y: 12), control1: CGPoint(x: 15, y: -7), control2: CGPoint(x: 12, y: 8))
                g.fill(leaf, with: .color(garden.leaf))
                var rib = Path()
                rib.move(to: CGPoint(x: 0, y: 11))
                rib.addLine(to: CGPoint(x: 0, y: -4))
                g.stroke(rib, with: .color(garden.leafDark), lineWidth: 1)
            }
            if kind == .back {
                for k in 0..<5 {
                    let a = Double(k) / 5 * 2 * Double.pi - Double.pi / 2
                    let x = 8 + cos(a) * 4, y = 6 + sin(a) * 4
                    g.fill(Path(ellipseIn: CGRect(x: x - 3.4, y: y - 3.4, width: 6.8, height: 6.8)), with: .color(garden.flower))
                }
                g.fill(Path(ellipseIn: CGRect(x: 5.6, y: 3.6, width: 4.8, height: 4.8)), with: .color(garden.flowerCore))
            }
            if kind == .leave {
                g.stroke(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: .color(Theme.accent), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 每週一條直條，滿格是 7 天，後面淡色帶是平常的範圍；這週用主色，其他用淡色
struct WeekBarsView: View {
    var card: WeekCard
    private static let full: CGFloat = 120 // domy-ignore: 圖表高度

    private func tall(_ days: Int) -> CGFloat { WeekBarsView.full * CGFloat(min(7, max(0, days))) / 7 }

    var body: some View {
        VStack(spacing: Sp.s2) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Rd.sm, style: .continuous)
                    .fill(Theme.soft)
                    .frame(height: max(Sp.s1, tall(card.hi) - tall(card.lo)))
                    .padding(.bottom, tall(card.lo))
                    .accessibilityHidden(true)
                HStack(alignment: .bottom, spacing: Sp.s2) {
                    ForEach(card.rows, id: \.start) { r in bar(r) }
                }
            }
            .frame(height: WeekBarsView.full, alignment: .bottom)
            HStack {
                Text(card.from)
                Spacer(minLength: 0)
                Text(Copy.t(.f1now))
            }
            .domyType(Ty.footnote)
            .foregroundStyle(Theme.fg2)
            .accessibilityHidden(true)
        }
    }

    private func bar(_ r: WeekBarData) -> some View {
        let week = r.current ? "這週" : r.start.short + "那週"
        let days = r.letgo ? "放手測試" : "\(r.done) 天"
        return RoundedRectangle(cornerRadius: Rd.sm, style: .continuous)
            .fill(r.current ? Theme.accent : Theme.accent.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: r.done == 0 ? Sz.hairline : tall(r.done))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(week)，\(days)")
    }
}

/// 一天一條線（清晨四點到隔天四點），每一次一個點，淡色帶是多半在做的那兩小時
struct TimeDots: View {
    var time: UsualTime
    private static let tall: CGFloat = 56 // domy-ignore: 圖表高度

    var body: some View {
        VStack(spacing: Sp.s2) {
            Canvas { ctx, size in
                let r = Sp.s1
                func X(_ minute: Int) -> CGFloat { r + (size.width - r * 2) * CGFloat(minute) / 1440 }
                let mid = size.height / 2
                let left = X(time.start) - r
                let right = X(min(1440, time.start + UsualTime.window)) + r
                let band = CGRect(x: left, y: 0, width: right - left, height: size.height)
                ctx.fill(Path(roundedRect: band, cornerRadius: Rd.sm, style: .continuous), with: .color(Theme.soft))
                var line = Path()
                line.move(to: CGPoint(x: 0, y: mid))
                line.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(line, with: .color(Theme.separator), lineWidth: Sz.hairline)
                for p in time.points {
                    ctx.fill(Path(ellipseIn: CGRect(x: X(p) - r, y: mid - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.accent.opacity(0.6)))
                }
            }
            .frame(height: TimeDots.tall)
            HStack {
                Text(Copy.t(.f5left))
                Spacer(minLength: 0)
                Text(Copy.t(.f5mid))
                Spacer(minLength: 0)
                Text(Copy.t(.f5right))
            }
            .domyType(Ty.footnote)
            .foregroundStyle(Theme.fg2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近 \(time.points.count) 次")
    }
}

/// 淡底一條，左邊填色
struct FillBar: View {
    /// 0 到 1
    var value: Double
    var color: Color
    var height: CGFloat

    var body: some View {
        Capsule()
            .fill(Theme.soft)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                }
            }
    }
}

/// 平日、週末各一條，底一樣長
struct RatioBar: View {
    var name: String
    var count: GroupCount

    private var words: String { Copy.t(.f2count, ["a": count.days, "b": count.done]) }

    var body: some View {
        VStack(spacing: Sp.s1) {
            HStack {
                Text(name)
                Spacer(minLength: Sp.s2)
                Text(words).monospacedDigit()
            }
            .domyType(Ty.subheadline)
            .foregroundStyle(Theme.fg)
            FillBar(value: count.rate, color: Theme.accent, height: Sp.s3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(words)")
    }
}

/// 竹籃與排隊：從田右上角推進來
struct BasketView: View {
    @Environment(Store.self) private var store
    @State private var queueText = ""
    @FocusState private var queueFocused: Bool
    @State private var picked: PotatoPick? = nil

    struct PotatoPick: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var body: some View {
        DomyScreen {
            basketSection
            queueSection
        }
        .sheet(item: $picked) { pick in
            if store.state.basket.indices.contains(pick.index) {
                PotatoSheet(potato: store.state.basket[pick.index])
            }
        }
    }

    // MARK: 排隊

    private var queueSection: some View {
        DomySection(title: "排隊") {
            ForEach(queueRows) { row in
                let i = row.index
                let q = row.text
                HStack(spacing: Sp.s3) {
                    Text("\(i + 1)")
                        .domyType(Ty.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg2)
                        .frame(width: Sp.s5)
                        .contentTransition(.numericText(value: Double(i)))
                    Text(q).domyType(Ty.body).foregroundStyle(Theme.fg)
                    Spacer(minLength: 0)
                    DomyButton("移除", variant: .quiet, size: .compact) {
                        Haptic.remove()
                        withAnimation(Feel.change) { store.removeQueue(at: i) }
                    }
                    .accessibilityLabel("移除 \(q)")
                }
                .padding(.leading, Sp.s4)
                .padding(.trailing, Sp.s2)
                .frame(minHeight: Sz.row)
                RowSep()
            }
            HStack(spacing: Sp.s2) {
                TextField("之後想種的，寫一行", text: $queueText)
                    .focused($queueFocused)
                    .submitLabel(.done)
                    .onSubmit { addQueue() }
                    .onChange(of: queueText) { _, v in if v.count > 40 { queueText = String(v.prefix(40)) } }
                    .domyField(focused: queueFocused)
                DomyButton("加入", size: .compact, disabled: queueText.trimmingCharacters(in: .whitespaces).isEmpty) { addQueue() }
            }
            .padding(Sp.s4)
        }
    }

    private func addQueue() {
        withAnimation(Feel.change) { store.addQueue(queueText) }
        queueText = ""
    }

    struct QueueRow: Identifiable {
        let id: String
        let index: Int
        let text: String
    }

    /// 每一列要有自己的身分，移掉中間那一列時才是那一列淡出、下面的往上補。
    /// 同樣的字可以排兩次，所以身分是「字＋第幾次出現」。
    private var queueRows: [QueueRow] {
        var seen: [String: Int] = [:]
        return store.state.queue.enumerated().map { i, q in
            let n = seen[q, default: 0]
            seen[q] = n + 1
            return QueueRow(id: "\(q)#\(n)", index: i, text: q)
        }
    }

    // MARK: 竹籃（Q12）

    private var basketSection: some View {
        DomySection {
            if store.state.basket.isEmpty {
                DomyEmptyState(icon: "basket", title: "竹籃還是空的", detail: "長好的習慣會收在這裡。")
            } else {
                ForEach(Array(store.state.basket.enumerated()), id: \.offset) { i, p in
                    if i > 0 { RowSep() }
                    Button { picked = PotatoPick(index: i) } label: {
                        HStack(spacing: Sp.s3) {
                            PotatoBadge()
                            VStack(alignment: .leading, spacing: Sp.s1 / 2) {
                                Text(p.floor).domyType(Ty.body).foregroundStyle(Theme.fg)
                                Text("\(p.nodes) 條根 · 回來 \(p.ret) 次 · \(p.days) 天")
                                    .domyType(Ty.footnote)
                                    .foregroundStyle(Theme.fg2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(Ty.footnote.font.weight(.semibold))
                                .foregroundStyle(Theme.fg3)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, Sp.s4)
                        .padding(.vertical, Sp.s3)
                        .frame(minHeight: Sz.row)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DomyRowPressStyle())
                }
            }
        }
    }

}

/// 開始四問的折線：y 是量表全幅 1 到 7（不寫數字），x 照日期（不是第幾次）；隔超過 10 天的兩點不連線（中間空了）
struct ChartView: View {
    var weekly: [WeeklyReview]

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s1) {
            axis(Copy.t(.f3top))
            line
            axis(Copy.t(.f3bottom))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("開始四問最近 \(weekly.count) 次，從 \(weekly.first?.date.short ?? "") 到 \(weekly.last?.date.short ?? "")")
    }

    private func axis(_ text: String) -> some View {
        Text(text)
            .domyType(Ty.footnote)
            .foregroundStyle(Theme.fg2)
    }

    private var line: some View {
        Canvas { ctx, size in
            let w = weekly
            guard !w.isEmpty else { return }
            let wd = Double(size.width)
            // 兩頭留出最後一點的半徑
            let pad = Double(Sp.s2)
            let iw = wd - pad * 2
            let ih = Double(size.height) - pad * 2
            let first = w[0].date.dayNumber
            let span = Double(max(1, w[w.count - 1].date.dayNumber - first))
            func X(_ i: Int) -> Double {
                w.count == 1 ? wd / 2 : pad + Double(w[i].date.dayNumber - first) / span * iw
            }
            func Y(_ v: Double) -> Double { pad + ih - (v - 1) / 6 * ih }

            for v in [1.0, 7.0] {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: Y(v)))
                grid.addLine(to: CGPoint(x: wd, y: Y(v)))
                ctx.stroke(grid, with: .color(Theme.separator), lineWidth: Sz.hairline)
            }

            let pts = w.enumerated().map { CGPoint(x: X($0.offset), y: Y($0.element.avg)) }
            var path = Path()
            for (i, p) in pts.enumerated() {
                let broken = i > 0 && w[i].date.dayNumber - w[i - 1].date.dayNumber > 10
                if i == 0 || broken { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(Theme.accent),
                       style: StrokeStyle(lineWidth: Sz.heroRingWidth, lineCap: .round, lineJoin: .round))
            for (i, p) in pts.enumerated() {
                let last = i == pts.count - 1
                let rr: CGFloat = last ? Sp.s1 + Sp.s1 / 2 : Sp.s1 / 2 + Sp.s1 / 4
                let dot = Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2))
                if last {
                    ctx.fill(dot, with: .color(Theme.surface))
                    ctx.stroke(dot, with: .color(Theme.accent), lineWidth: Sz.heroRingWidth)
                } else {
                    ctx.fill(dot, with: .color(Theme.accent))
                }
            }
        }
        .frame(height: 110) // domy-ignore: 圖表高度
    }
}
