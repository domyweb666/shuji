import SwiftUI

/// 田：根的數字、開始四問的曲線、長好了嗎三個訊號、排隊、竹籃。
struct FieldView: View {
    @Environment(Store.self) private var store
    @State private var queueText = ""
    @FocusState private var queueFocused: Bool
    @State private var showReview = false
    @State private var picked: PotatoPick? = nil
    @State private var showWeekAdvice = false
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
                statsSection
                reviewSection
                grownSection
                if AIClient.shared.isAvailable && store.state.auditReady(today: t) {
                    auditSection
                }
            }
            queueSection
            basketSection
        }
        .sheet(isPresented: $showReview) { ReviewSheet() }
        .sheet(isPresented: $showWeekAdvice) { WeekAdviceSheet() }
        .sheet(isPresented: $showAudit) { AuditSheet() }
        .sheet(isPresented: $showPaywall) { PaywallSheet() }
        .sheet(item: $picked) { pick in
            if store.state.basket.indices.contains(pick.index) {
                PotatoSheet(potato: store.state.basket[pick.index])
            }
        }
    }

    // MARK: 數字

    private var statsSection: some View {
        let st = store.state.stats(today: t)
        return VStack(alignment: .leading, spacing: Sp.s2) {
            DomyStatGrid(items: [
                DomyStat(value: "\(st.nodes)", unit: "條", label: "根"),
                DomyStat(value: "\(st.ret)", unit: "次", label: "回來"),
                DomyStat(value: "\(st.missed)", unit: "天", label: "漏掉"),
                DomyStat(value: "\(st.leaves)／\(store.state.settings.leave)", label: "本月請假"),
            ])
            Foot("種下去那天 \(store.state.habit?.planted.short ?? "")。只數做了的，不數連續。漏掉的日子不會讓藤枯掉。")
        }
    }

    // MARK: 開始四問

    private var reviewSection: some View {
        DomySection(title: "開始四問") {
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
            RowSep()
            RowButton(text: "做這週的開始四問", tone: .action) { showReview = true }
            if AIClient.shared.isAvailable && store.state.weeklyAdviceReady(today: t) {
                RowSep()
                RowButton(text: "這週看什麼", value: purchases.isFull ? nil : "完整版", tone: .action) {
                    if purchases.isFull { showWeekAdvice = true } else { showPaywall = true }
                }
            }
        }
    }

    // MARK: 季稽核

    private var auditSection: some View {
        DomySection(title: "季稽核", footer: "種滿一季了。看看這個習慣要維持、加量、換情境，還是退場。") {
            RowButton(text: "做這一季的稽核", value: purchases.isFull ? nil : "完整版", tone: .action) {
                if purchases.isFull { showAudit = true } else { showPaywall = true }
            }
        }
    }

    // MARK: 長好了嗎

    private var grownSection: some View {
        let sg = store.state.signals()
        return DomySection(title: "長好了嗎",
                           footer: "三個訊號有兩個通過就算長好了。" + (store.state.queue.first.map { "挖出來之後，下一個是「\($0)」。" } ?? "")) {
            signalRow(ok: sg.s1, title: "曲線走平",
                      mini: "最近三週相差 0.5 以內" + (sg.n < 6 ? "，至少要 6 週（現在 \(sg.n)）" : ""))
            RowSep()
            signalRow(ok: sg.s2, title: "壓力週還照做",
                      mini: "最近最忙、出遠門或不舒服的那週，有做最小一步，而且沒怎麼掙扎")
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
                Text("有些事會一直需要你出力，這也沒關係。要不要看看開關和最小一步？")
                    .domyType(Ty.subheadline)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var letgoMini: String {
        if store.state.letgo != nil { return "放手測試進行中" }
        if let r = store.state.letgoResult { return "放手兩週，回想做了 \(r.days) 天（之前兩週 \(r.prior) 天）" }
        return "兩週不記，看做的天數有沒有變少"
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

    // MARK: 竹籃

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
}

/// 開始四問的折線：y 軸 1 到 7，只標頭尾兩個日期
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
            func X(_ i: Int) -> Double { l + (w.count == 1 ? iw / 2 : Double(i) * iw / Double(w.count - 1)) }
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
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: Y(1)))
            area.addLine(to: CGPoint(x: pts[0].x, y: Y(1)))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [Theme.soft, Theme.soft.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: Y(1))))
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
        .accessibilityLabel("開始四問最近 \(weekly.count) 週")
    }
}
