import SwiftUI

/// 田：根的數字、開始四問的曲線、長好了嗎三個訊號、排隊、竹籃。
struct FieldView: View {
    @Environment(Store.self) private var store
    @State private var queueText = ""
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let h = store.state.habit {
                    BigTitle(title: "田", sub: "\(h.trigger) → \(h.floor)")
                    statsCard
                    reviewSection
                    grownSection
                    if AIClient.shared.isAvailable && store.state.auditReady(today: t) {
                        auditSection
                    }
                } else {
                    BigTitle(title: "田", sub: "還沒種東西")
                }
                queueSection
                basketSection
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 560)
            .padding(.top, 44)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
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

    private var statsCard: some View {
        let st = store.state.stats(today: t)
        return Group {
            Card {
                RowLabel(text: "根", value: "\(st.nodes) 條")
                RowSep()
                RowLabel(text: "回來／漏掉", value: "\(st.ret) 次／\(st.missed) 天")
                RowSep()
                RowLabel(text: "本月請假", value: "\(st.leaves)／\(store.state.settings.leave)")
                RowSep()
                RowLabel(text: "種下去那天", value: store.state.habit?.planted.short ?? "")
            }
            Foot("只數做了的，不數連續。漏掉的日子不會讓藤枯掉。")
        }
    }

    private var reviewSection: some View {
        Group {
            SectionTitle("開始四問")
            Card {
                if store.state.weekly.isEmpty {
                    Text("每週做一次開始四問，這裡會畫出一條線。它會先爬、後來走平，走平就是快長好了。")
                        .font(.subheadline).foregroundStyle(Theme.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 22, leading: 18, bottom: 22, trailing: 18))
                } else {
                    ChartView(weekly: Array(store.state.weekly.suffix(8)))
                        .padding(EdgeInsets(top: 14, leading: 12, bottom: 8, trailing: 12))
                }
                RowButton(text: "做這週的開始四問", color: Theme.accent) { showReview = true }
                if AIClient.shared.isAvailable && store.state.weeklyAdviceReady(today: t) {
                    RowSep()
                    RowButton(text: "這週看什麼", value: purchases.isFull ? nil : "完整版", color: Theme.accent) {
                        if purchases.isFull { showWeekAdvice = true } else { showPaywall = true }
                    }
                }
            }
        }
    }

    private var auditSection: some View {
        Group {
            SectionTitle("季稽核")
            Card {
                RowButton(text: "做這一季的稽核", value: purchases.isFull ? nil : "完整版", color: Theme.accent) {
                    if purchases.isFull { showAudit = true } else { showPaywall = true }
                }
            }
            Foot("種滿一季了。看看這個習慣要維持、加量、換情境，還是退場。")
        }
    }

    private var grownSection: some View {
        let sg = store.state.signals()
        return Group {
            SectionTitle("長好了嗎")
            Card {
                signalRow(ok: sg.s1, title: "曲線走平",
                          mini: "最近三週相差 0.5 以內" + (sg.n < 6 ? "，至少要 6 週（現在 \(sg.n)）" : ""))
                RowSep()
                signalRow(ok: sg.s2, title: "壓力週還照做",
                          mini: "最近最忙、出遠門或不舒服的那週，有做最小一步，而且沒怎麼掙扎")
                if store.state.pressure != true {
                    pillRow {
                        PillButton(title: "有，照做了", primary: true) { store.setPressure(true) }
                        PillButton(title: "還沒遇到／那週掉了") { store.setPressure(false) }
                    }
                }
                RowSep()
                signalRow(ok: sg.s3, title: "不記也照做", mini: letgoMini)
                if store.state.letgo == nil && !sg.s3 {
                    pillRow {
                        PillButton(title: "開始放手測試") { store.startLetGo() }
                    }
                }
                if sg.flatLow {
                    RowSep()
                    Text("有些事會一直需要你出力，這也沒關係。要不要看看開關和最小一步？")
                        .font(.system(size: 14)).foregroundStyle(Theme.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.rowInset).padding(.vertical, 12)
                }
                if sg.passCount >= 2 {
                    pillRow {
                        PillButton(title: "挖地瓜", primary: true) { store.dig() }
                    }
                }
            }
            Foot("三個訊號有兩個通過就算長好了。" + (store.state.queue.first.map { "挖出來之後，下一個是「\($0)」。" } ?? ""))
        }
    }

    private var letgoMini: String {
        if store.state.letgo != nil { return "放手測試進行中" }
        if let r = store.state.letgoResult { return "放手兩週，回想做了 \(r.days) 天（之前兩週 \(r.prior) 天）" }
        return "兩週不記，看做的天數有沒有變少"
    }

    private func signalRow(ok: Bool, title: String, mini: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SignalDot(ok: ok).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(mini).font(.footnote).foregroundStyle(Theme.fg2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 12)
    }

    private func pillRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        FlowLayout(spacing: 8) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 0, leading: Theme.rowInset, bottom: 14, trailing: Theme.rowInset))
    }

    private var queueSection: some View {
        Group {
            SectionTitle("排隊")
            Card {
                ForEach(Array(store.state.queue.enumerated()), id: \.offset) { i, q in
                    HStack(spacing: 12) {
                        Text(q)
                        Spacer()
                        Button("移除") { store.removeQueue(at: i) }
                            .font(.subheadline).foregroundStyle(Theme.accent)
                            .accessibilityLabel("移除 \(q)")
                    }
                    .padding(.horizontal, Theme.rowInset)
                    .frame(minHeight: Theme.rowHeight)
                    RowSep()
                }
                HStack(spacing: 12) {
                    TextField("之後想種的，寫一行", text: $queueText)
                        .submitLabel(.done)
                        .onSubmit { addQueue() }
                        .onChange(of: queueText) { _, v in if v.count > 40 { queueText = String(v.prefix(40)) } }
                    Button("加入") { addQueue() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, Theme.rowInset)
                .frame(minHeight: Theme.rowHeight)
            }
            Foot("一次種一個。兩個都還在長的時候，會搶同一份注意力。這一個長好、挖出來之後，排第一的會出現在種下一個的畫面。")
        }
    }

    private func addQueue() {
        store.addQueue(queueText)
        queueText = ""
    }

    private var basketSection: some View {
        Group {
            SectionTitle("竹籃")
            Card {
                if store.state.basket.isEmpty {
                    Text("長好的習慣會變成一顆地瓜，收在這裡。")
                        .font(.subheadline).foregroundStyle(Theme.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 22, leading: 18, bottom: 22, trailing: 18))
                } else {
                    ForEach(Array(store.state.basket.enumerated()), id: \.offset) { i, p in
                        if i > 0 { RowSep() }
                        Button { picked = PotatoPick(index: i) } label: {
                            HStack(spacing: 12) {
                                PotatoView(width: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.floor)
                                    Text("\(p.nodes) 條根 · 回來 \(p.ret) 次 · \(p.days) 天")
                                        .font(.footnote).foregroundStyle(Theme.fg2)
                                }
                                Spacer(minLength: 0)
                                Text("›").font(.system(size: 20)).foregroundStyle(Theme.fg3)
                            }
                            .padding(.horizontal, Theme.rowInset)
                            .padding(.vertical, 10)
                            .frame(minHeight: Theme.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
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
            let wd = size.width
            let hd = size.height
            let l = 26.0, r = 12.0, top = 12.0, bottom = 26.0
            let iw = wd - l - r
            let ih = hd - top - bottom
            func X(_ i: Int) -> Double { l + (w.count == 1 ? iw / 2 : Double(i) * iw / Double(w.count - 1)) }
            func Y(_ v: Double) -> Double { top + ih - (v - 1) / 6 * ih }

            for v in [1.0, 4.0, 7.0] {
                var grid = Path()
                grid.move(to: CGPoint(x: l, y: Y(v)))
                grid.addLine(to: CGPoint(x: wd - r, y: Y(v)))
                ctx.stroke(grid, with: .color(Theme.sep), lineWidth: 1)
                ctx.draw(Text("\(Int(v))").font(.system(size: 11)).foregroundStyle(Theme.fg2),
                         at: CGPoint(x: l - 8, y: Y(v)), anchor: .trailing)
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
            ctx.fill(area, with: .color(Theme.accentSoft))
            ctx.stroke(line, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for (i, p) in pts.enumerated() {
                let rr = i == pts.count - 1 ? 4.5 : 2.5
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(Theme.accent))
            }
            ctx.draw(Text(w[0].date.short).font(.system(size: 11)).foregroundStyle(Theme.fg2),
                     at: CGPoint(x: X(0), y: hd - 2), anchor: .bottom)
            if w.count > 1 {
                ctx.draw(Text(w[w.count - 1].date.short).font(.system(size: 11)).foregroundStyle(Theme.fg2),
                         at: CGPoint(x: X(w.count - 1), y: hd - 2), anchor: .bottom)
            }
        }
        .frame(height: 150)
        .accessibilityLabel("開始四問最近 \(weekly.count) 週")
    }
}
