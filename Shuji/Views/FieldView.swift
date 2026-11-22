import SwiftUI

/// 田（細查層，.analytics/06）：每一區回答一題。
/// 長好了嗎（Q6）→ 開始四問（Q4）→ 這幾週記了幾天（Q11）→ 漏掉的日子有沒有規律（Q5）→ 季稽核 → 排隊 → 竹籃（Q12）。
/// 原本最上面的四個統計數字拿掉了：看完不會改任何事（審查 P1-9）。
struct FieldView: View {
    @Environment(Store.self) private var store
    @State private var queueText = ""
    @FocusState private var queueFocused: Bool
    @State private var week: WeekSheet.Start? = nil
    @State private var picked: PotatoPick? = nil
    @State private var showAudit = false
    @State private var showPaywall = false
    private let purchases = Purchases.shared

    struct PotatoPick: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private var t: DayKey { store.today }

    var body: some View {
        DomyScreen(title: "田", sub: store.state.habit.map { "\($0.trigger) → \($0.floor)" } ?? "還沒種東西") {
            if store.state.habit != nil {
                grownSection
                reviewSection
                weeksSection
                patternSection
                if AIClient.shared.isAvailable && store.state.auditReady(today: t) {
                    auditSection
                }
            }
            queueSection
            basketSection
        }
        .sheet(item: $week) { start in WeekSheet(start: start) }
        .sheet(isPresented: $showAudit) { AuditSheet() }
        .sheet(isPresented: $showPaywall) { PaywallSheet() }
        .sheet(item: $picked) { pick in
            if store.state.basket.indices.contains(pick.index) {
                PotatoSheet(potato: store.state.basket[pick.index])
            }
        }
    }

    // MARK: 長好了嗎（Q6）

    private var grownSection: some View {
        let sg = store.state.signals(today: t)
        let planted = store.state.habit?.planted ?? t
        var footer = Copy.t(.d1, ["date": planted.short, "n": DayKey.days(from: planted, to: t) + 1])
        if let next = store.state.queue.first { footer += Copy.t(.d1next, ["next": next]) }
        return DomySection(title: "長好了嗎", footer: footer) {
            signalRow(ok: sg.s1, title: "曲線走平", mini: curveMini(sg))
            RowSep()
            signalRow(ok: sg.s2, title: "壓力週還照做", mini: pressureMini)
            if store.state.pressure != true {
                pillRow {
                    DomyButton("有，照做了", size: .compact) { store.setPressure(true) }
                    DomyButton("還沒遇到／那週掉了", variant: .secondary, size: .compact) { store.setPressure(false) }
                }
            }
            RowSep()
            signalRow(ok: sg.s3, title: "不記也照做", mini: letgoMini)
            if store.state.letgo == nil && !sg.s3 {
                pillRow {
                    DomyButton("開始放手測試", variant: .secondary, size: .compact) { store.startLetGo() }
                }
            }
            if sg.flatLow {
                RowSep()
                VStack(alignment: .leading, spacing: Sp.s2) {
                    Text(Copy.t(.d5))
                        .domyType(Ty.subheadline)
                        .foregroundStyle(Theme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                    DomyButton(Copy.t(.d5button), variant: .plain, size: .compact) { goSettings(.trigger) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Sp.s4)
                .padding(.vertical, Sp.s3)
            }
            if sg.passCount >= 2 {
                RowSep()
                DomyButton("挖地瓜") { store.dig() }
                    .padding(Sp.s4)
            }
        }
    }

    private func curveMini(_ sg: AppState.Signals) -> String {
        if sg.n < 6 { return Copy.t(.d2few, ["n": sg.n]) }
        if sg.stale, let last = store.state.weekly.last { return Copy.t(.d2stale, ["date": last.date.short]) }
        if sg.spread { return Copy.t(.d2spread) }
        return Copy.t(.d2)
    }

    private var pressureMini: String {
        guard let answer = store.state.pressure, let day = store.state.pressureDay else { return Copy.t(.d3) }
        return Copy.t(.d3) + "\n" + Copy.t(answer ? .d3yes : .d3no, ["date": day.short])
    }

    private var letgoMini: String {
        if let lg = store.state.letgo { return Copy.t(.d4running, ["date": lg.start.adding(13).short]) }
        if let r = store.state.letgoResult {
            if let days = r.recalled { return Copy.t(.d4result, ["r": days, "p": r.prior]) }
            return Copy.t(.d4unsure)
        }
        return Copy.t(.d4)
    }

    private func signalRow(ok: Bool, title: String, mini: String) -> some View {
        HStack(alignment: .top, spacing: Sp.s3) {
            SignalDot(ok: ok)
            VStack(alignment: .leading, spacing: Sp.s1 / 2) {
                Text(title).domyType(Ty.body).foregroundStyle(Theme.fg)
                Text(mini)
                    .domyType(Ty.footnote)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
        .accessibilityElement(children: .combine)
    }

    private func pillRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        FlowLayout(spacing: Sp.s2) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Sp.s4 + Sp.s6 + Sp.s3)
            .padding(.trailing, Sp.s4)
            .padding(.bottom, Sp.s3)
    }

    // MARK: 開始四問（Q4）

    private var reviewSection: some View {
        let e = store.state.reportWeekEnd(today: t)
        return DomySection(title: "開始四問") {
            if store.state.weekly.isEmpty {
                DomyEmptyState(icon: "chart.line.uptrend.xyaxis",
                               title: "還沒有線",
                               detail: "每週做一次開始四問，這裡會畫出一條線。它會先爬、後來走平，走平就是快長好了。")
            } else {
                ChartView(weekly: Array(store.state.weekly.suffix(8)))
                    .padding(.horizontal, Sp.s3)
                    .padding(.top, Sp.s4)
                    .padding(.bottom, Sp.s2)
            }
            if !store.state.reviewedThisWeek(today: t) {
                RowSep()
                RowButton(text: Copy.t(.d6do), tone: .action) { week = .review }
            }
            RowSep()
            RowButton(text: Copy.t(.d6week), value: Copy.t(.w0s, ["start": e.adding(-6).short, "end": e.short])) {
                week = .report
            }
        }
    }

    // MARK: 這幾週記了幾天（Q11）

    private var weeksSection: some View {
        let rows = store.state.recentWeeks(today: t)
        let planted = store.state.habit?.planted ?? t
        let age = DayKey.days(from: planted, to: t) + 1
        return DomySection(title: Copy.t(.d7title), footer: age >= 7 ? Copy.t(.d7foot) : nil) {
            if age < 7 || rows.isEmpty {
                CardBody { Text(Copy.t(.d7few, ["d": age])).domyType(Ty.subheadline).foregroundStyle(Theme.fg2) }
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { RowSep() }
                    WeekRowView(row: row)
                }
            }
        }
    }

    // MARK: 漏掉的日子有沒有規律（Q5）

    private var patternSection: some View {
        let l = store.state.ledger(today: t)
        let e = store.state.reportWeekEnd(today: t)
        let split = l.weekendSplit(end: e)
        let hasTravel = l.hasTravel(end: e)
        let travel = l.travelSplit(end: e)
        let reasons = l.leaveReasons()
        return DomySection(title: Copy.t(.d8title)) {
            patternLine(highlight: split.passes) {
                if split.enough {
                    Text(Copy.t(.d8counts, ["w": split.weeks, "a": split.b.days, "b": split.b.done,
                                            "c": split.a.days, "d": split.a.done]))
                        .domyType(Ty.body).foregroundStyle(Theme.fg)
                    Text(Copy.t(split.passes ? .d8over : .d8below)).domyType(Ty.footnote).foregroundStyle(Theme.fg2)
                } else {
                    Text(Copy.t(.d8few, ["k": max(1, split.needWeeks)])).domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
                }
                if split.pausedDays > 0 {
                    Text(Copy.t(.d8pause, ["g": split.pausedDays])).domyType(Ty.footnote).foregroundStyle(Theme.fg2)
                }
            }
            if hasTravel {
                RowSep()
                patternLine(highlight: travel.passes) {
                    if travel.a.days >= Threshold.groupDays && travel.b.days >= Threshold.groupDays {
                        Text(Copy.t(.d8travel, ["a": travel.a.days, "b": travel.a.done, "c": travel.b.days, "d": travel.b.done]))
                            .domyType(Ty.body).foregroundStyle(Theme.fg)
                        Text(Copy.t(travel.passes ? .d8over : .d8below)).domyType(Ty.footnote).foregroundStyle(Theme.fg2)
                    } else {
                        Text(Copy.t(.d8travelFew)).domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
                    }
                }
            }
            if !reasons.isEmpty {
                RowSep()
                let list = reasons.prefix(3).map { "\($0.reason.isEmpty ? Copy.t(.d8noReason) : $0.reason) \($0.count) 次" }
                    .joined(separator: "、")
                patternLine(highlight: false) {
                    Text(Copy.t(.d8leaves, ["n": reasons.reduce(0) { $0 + $1.count }, "list": list]))
                        .domyType(Ty.subheadline).foregroundStyle(Theme.fg)
                }
            }
            if let trial = store.state.runningTrial {
                RowSep()
                if t >= trial.end {
                    patternLine(highlight: false) {
                        Text(Copy.t(.d9due)).domyType(Ty.subheadline).foregroundStyle(Theme.fg)
                    }
                    RowButton(text: Copy.t(.d9look), tone: .action) { week = .report }
                } else {
                    patternLine(highlight: false) {
                        Text(Copy.t(.d9, ["change": Copy.changeLabel(trial.change, group: trial.group),
                                          "date": trial.end.adding(-1).short]))
                            .domyType(Ty.subheadline).foregroundStyle(Theme.fg)
                    }
                    RowButton(text: Copy.t(.d9stop), chevron: false) { store.stopTrial(trial.id) }
                }
            }
        }
    }

    /// 細查層的一句；過門檻的那一句用主色細框（突顯只用在一處）
    private func patternLine<Content: View>(highlight: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Sp.s1) { content() }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Sp.s4)
            .padding(.vertical, Sp.s3)
            .overlay {
                if highlight {
                    RoundedRectangle(cornerRadius: Rd.md, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: Sz.hairline * 1.5)
                        .padding(Sp.s1)
                }
            }
    }

    // MARK: 季稽核（完整版，AI）

    private var auditSection: some View {
        DomySection(title: "季稽核", footer: "種滿一季了。看看這個習慣要維持、加量、換情境，還是退場。") {
            RowButton(text: "做這一季的稽核", value: purchases.isFull ? nil : "完整版", tone: .action) {
                if purchases.isFull { showAudit = true } else { showPaywall = true }
            }
        }
    }

    // MARK: 排隊

    private var queueSection: some View {
        DomySection(title: "排隊",
                    footer: "一次種一個。兩個都還在長的時候，會搶同一份注意力。這一個長好、挖出來之後，排第一的會出現在種下一個的畫面。") {
            ForEach(Array(store.state.queue.enumerated()), id: \.offset) { i, q in
                HStack(spacing: Sp.s3) {
                    Text("\(i + 1)")
                        .domyType(Ty.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.fg2)
                        .frame(width: Sp.s5)
                    Text(q).domyType(Ty.body).foregroundStyle(Theme.fg)
                    Spacer(minLength: 0)
                    DomyButton("移除", variant: .quiet, size: .compact) { store.removeQueue(at: i) }
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
        store.addQueue(queueText)
        queueText = ""
    }

    // MARK: 竹籃（Q12）

    private var basketSection: some View {
        DomySection(title: "竹籃") {
            if store.state.basket.isEmpty {
                DomyEmptyState(icon: "basket", title: "竹籃還是空的", detail: "長好的習慣會變成一顆地瓜，收在這裡。")
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

    private func goSettings(_ target: SettingsTarget) {
        store.settingsTarget = target
        withAnimation(.easeInOut(duration: DomyTokens.Motion.transition)) { store.page = 2 }
    }
}

extension WeekSheet.Start: Identifiable {
    var id: Int { self == .review ? 0 : 1 }
}

/// 「這幾週記了幾天」的一列：日期、從 0 開始的橫條（實心記了、空心請假，滿格 7 天）、天數
struct WeekRowView: View {
    var row: WeekRow

    var body: some View {
        let c = row.count
        HStack(alignment: .center, spacing: Sp.s3) {
            Text("\(c.start.short)–\(c.end.short)")
                .domyType(Ty.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.fg2)
                .frame(minWidth: Sp.s12 + Sp.s8, alignment: .leading)
            VStack(alignment: .leading, spacing: Sp.s1) {
                switch row.kind {
                case .bar:
                    WeekBar(done: c.done, leave: c.leave)
                    HStack(spacing: Sp.s2) {
                        Text(c.leave > 0 ? Copy.t(.d7leave, ["n": c.done, "m": c.leave]) : Copy.t(.d7row, ["n": c.done]))
                            .domyType(Ty.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.fg)
                        if c.todayPending {
                            Text(Copy.t(.d7today)).domyType(Ty.footnote).foregroundStyle(Theme.fg2)
                        }
                    }
                case .empty:
                    Text(Copy.t(.d7empty)).domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
                case .letgo:
                    Text(Copy.t(.d7letgo)).domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
                case .first:
                    Text(Copy.t(.d7first, ["d": row.plantedDays, "n": c.done]))
                        .domyType(Ty.subheadline)
                        .foregroundStyle(Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if row.changed {
                    Chip(Copy.t(.d7changed))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
        .accessibilityElement(children: .combine)
    }
}

/// 一週的橫條：從同一條左邊線開始，滿格是 7 天；記了是實心，請假是空心接在後面
struct WeekBar: View {
    var done: Int
    var leave: Int

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 7
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceMuted)
                HStack(spacing: 0) {
                    if done > 0 {
                        Capsule().fill(Theme.accent).frame(width: unit * CGFloat(min(done, 7)))
                    }
                    if leave > 0 {
                        Capsule().strokeBorder(Theme.accent, lineWidth: Sz.hairline * 1.5)
                            .frame(width: unit * CGFloat(min(leave, max(0, 7 - done))))
                    }
                }
            }
        }
        .frame(height: Sp.s2)
        .accessibilityHidden(true)
    }
}

/// 開始四問的折線：y 是量表全幅 1 到 7，x 照日期（不是第幾次）；隔超過 10 天的兩點不連線（中間空了）
struct ChartView: View {
    var weekly: [WeeklyReview]

    var body: some View {
        Canvas { ctx, size in
            let w = weekly
            guard !w.isEmpty else { return }
            let wd = Double(size.width)
            let hd = Double(size.height)
            let l = Double(Sp.s6), r = Double(Sp.s3), top = Double(Sp.s3), bottom = Double(Sp.s6)
            let gap = Double(Sp.s2)
            let iw = wd - l - r
            let ih = hd - top - bottom
            let first = w[0].date.dayNumber
            let span = Double(max(1, w[w.count - 1].date.dayNumber - first))
            func X(_ i: Int) -> Double {
                w.count == 1 ? l + iw / 2 : l + Double(w[i].date.dayNumber - first) / span * iw
            }
            func Y(_ v: Double) -> Double { top + ih - (v - 1) / 6 * ih }

            for v in [1.0, 4.0, 7.0] {
                var grid = Path()
                grid.move(to: CGPoint(x: l, y: Y(v)))
                grid.addLine(to: CGPoint(x: wd - r, y: Y(v)))
                ctx.stroke(grid, with: .color(Theme.separator), lineWidth: Sz.hairline)
                ctx.draw(Text("\(Int(v))").font(Ty.caption.font).foregroundStyle(Theme.fg2),
                         at: CGPoint(x: l - gap, y: Y(v)), anchor: .trailing)
            }

            let pts = w.enumerated().map { CGPoint(x: X($0.offset), y: Y($0.element.avg)) }
            var line = Path()
            for (i, p) in pts.enumerated() {
                let broken = i > 0 && w[i].date.dayNumber - w[i - 1].date.dayNumber > 10
                if i == 0 || broken { line.move(to: p) } else { line.addLine(to: p) }
            }
            ctx.stroke(line, with: .color(Theme.accent),
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
            ctx.draw(Text(w[0].date.short).font(Ty.caption.font).foregroundStyle(Theme.fg2),
                     at: CGPoint(x: X(0), y: hd - 2), anchor: .bottom)
            if w.count > 1 {
                ctx.draw(Text(w[w.count - 1].date.short).font(Ty.caption.font).foregroundStyle(Theme.fg2),
                         at: CGPoint(x: X(w.count - 1), y: hd - 2), anchor: .bottom)
            }
        }
        .frame(height: 160) // domy-ignore: 圖表高度
        .accessibilityLabel("開始四問最近 \(weekly.count) 次，從 \(weekly.first?.date.short ?? "") 到 \(weekly.last?.date.short ?? "")")
    }
}
