import SwiftUI

/// 主畫面「今天」。狀態照原型 renderMain 的順序：
/// 挖出來了 → 放手測試 → 停了超過兩週 → 今天做了 → 今天跳過 → 還沒做（按住）。
/// 版面（Claude Design 方向 C，QC-0004 多米選的）：日期一行（右邊跳過／復原）→ 習慣那句當大標題 → 土面的藤 → 土裡那顆地瓜。
/// 地瓜就是核心大鈕，記好、跳過、放手時同一個位置換樣子。要讀的字都在土面上，土裡只有地瓜上的字。
struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.domyBottomInset) private var bottomInset
    @State private var sheet: TodaySheet? = nil

    /// 土面以上：一片葉子加捲鬚的高度
    private static let vineAbove: CGFloat = 60 // domy-ignore: 插畫畫布高度
    /// 土面到地瓜那一塊：留給根。字多、畫面矮的時候先縮這裡，地瓜的位置不動
    private static let rootGap: CGFloat = 76 // domy-ignore: 插畫畫布高度
    private static let rootGapMin: CGFloat = 36 // domy-ignore: 插畫畫布高度
    /// 地瓜外框上緣到外圈上緣
    private static let ringInset: CGFloat = 20 // domy-ignore: 插畫尺寸

    enum TodaySheet: String, Identifiable {
        case skip
        case tips
        case diagnose
        case stuck
        case next
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if store.state.justDug != nil {
                DugView()
            } else if store.showLetGoEnd {
                LetGoEndView()
            } else {
                content
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .skip: SkipSheet()
            case .tips: TipsSheet()
            case .diagnose: DiagnoseSheet()
            case .stuck: StuckSheet { stuck($0) }
            case .next: NextHabitSheet()
            }
        }
    }

    private var t: DayKey { store.today }

    private var content: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: Sp.s5) {
                        header
                        words
                    }
                    .animation(Feel.transition, value: store.state.log(on: t)?.t)
                    .padding(.horizontal, Sz.screenMargin)
                    .padding(.top, Theme.pageTop)
                    .frame(maxWidth: Theme.contentMaxWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Sp.s2)
                    soil
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.canvas)
    }

    private var header: some View {
        let st = store.state.stats(today: t)
        return HStack(spacing: Sp.s2) {
            Text(GlanceCopy.todaySub(date: t.long, nodes: st.nodes))
                .domyType(Ty.subheadline)
                .foregroundStyle(Theme.fg2)
                .contentTransition(.numericText())
                .animation(Feel.change, value: st.nodes)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if store.state.habit != nil && store.state.letgo == nil { corner }
        }
        .frame(minHeight: Sz.iconButton)
    }

    /// 還沒記是「跳過」，記了或跳過了是「復原」
    @ViewBuilder
    private var corner: some View {
        if store.state.log(on: t) == nil {
            HeaderPill(title: "跳過") { sheet = .skip }
        } else {
            HeaderPill(title: "復原") {
                Haptic.remove()
                store.undoToday()
            }
        }
    }

    // MARK: 土面上的字

    @ViewBuilder
    private var words: some View {
        if let h = store.state.habit {
            let floor = store.state.activeFloor
            if let left = store.state.letgoDaysLeft(today: t) {
                Sentence(trigger: h.trigger, floor: floor)
                note("放手測試中，照常做就好，不用記。還有 \(left) 天。")
                // 這兩週沒事做，快長好了：先想下一個
                if store.state.queue.isEmpty, AIClient.shared.isAvailable {
                    textLink("先想下一個要種什麼") { sheet = .next }
                }
            } else if store.state.longAbsence(today: t) {
                absence(h)
            } else if store.state.log(on: t) != nil {
                // 記好、跳過之後只留這句，今天的樣子交給地瓜
                Sentence(trigger: h.trigger, floor: floor)
                if store.state.returnedFromLong(today: t) { textLink("上次卡在哪？") { sheet = .stuck } }
            } else {
                Sentence(trigger: h.trigger, floor: floor)
                if store.state.consecutiveMissed(today: t) >= 2 {
                    if AIClient.shared.isAvailable {
                        textLink("連著沒做，找找看哪裡卡住") { sheet = .diagnose }
                    } else {
                        textLink("卡住的話，看看時機對不對，或最小一步太大") { goSentence(nil) }
                    }
                    if !h.backup.isEmpty { note("不順的時候：\(h.backup)") }
                }
            }
        }
    }

    @ViewBuilder
    private func absence(_ h: Habit) -> some View {
        // 先歡迎，卡在哪等接上了再問
        VStack(alignment: .leading, spacing: Sp.s2) {
            Text("你回來了")
                .domyType(Ty.title1)
                .foregroundStyle(Theme.fg)
            Text("藤還在，根都還在。")
                .domyType(Ty.title3)
                .foregroundStyle(Theme.fg)
            if !h.why.isEmpty {
                Text("你說這是為了：\(h.why)")
                    .domyType(Ty.subheadline)
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Text("如果\(h.trigger)，我就\(store.state.activeFloor)。")
            .domyType(Ty.headline)
            .foregroundStyle(Theme.fg)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stuck(_ c: StuckSheet.Choice) {
        switch c {
        case .tips: sheet = .tips
        case .diagnose: sheet = .diagnose
        case .trigger, .floor:
            sheet = nil
            goSentence(c == .trigger ? .trigger : .floor)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .domyType(Ty.body)
            .foregroundStyle(Theme.fg)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 靠左的文字連結，可以換行
    private func textLink(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .domyType(Ty.callout)
                .foregroundStyle(Theme.strong)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: Sz.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(DomyPressStyle())
        // 44 點的點擊高度上下各多出一截，扣掉才跟別的段落一樣遠
        .padding(.vertical, -Sp.s3)
    }

    // MARK: 土

    /// 藤、土和地瓜。地瓜底下讓出分頁列，離畫面底的距離固定
    private var soil: some View {
        let fixed = TodayView.vineAbove + PotatoBody<EmptyView>.frameSize.height + Sp.s2 + bottomInset
        return GeometryReader { geo in
            let top = TodayView.vineAbove + geo.size.height - fixed
            VineView(soilTop: TodayView.vineAbove, potatoTop: top + TodayView.ringInset, baked: baked)
                .overlay(alignment: .top) {
                    potato
                        .padding(.top, top)
                        .animation(Feel.transition, value: store.state.log(on: t)?.t)
                }
        }
        .frame(minHeight: fixed + TodayView.rootGapMin, maxHeight: fixed + TodayView.rootGap)
        .layoutPriority(1)
    }

    /// 今天記好了，地瓜烤好剝開
    private var baked: Bool {
        store.state.letgoDaysLeft(today: t) == nil && store.state.log(on: t)?.t == .done
    }

    @ViewBuilder
    private var potato: some View {
        let log = store.state.log(on: t)
        if store.state.letgoDaysLeft(today: t) != nil {
            PotatoSeal(icon: "hourglass", title: "放手中")
        } else if let log, log.t == .leave {
            PotatoSkip(reason: log.reason ?? "")
        } else {
            HoldButton(hint: store.state.longAbsence(today: t) ? "從這一節接上" : "做完最小一步，按住一下",
                       done: log?.t == .done,
                       back: log?.t == .done && store.state.isReturn(t)) { recordNode() }
        }
    }

    /// 聲音跟手機側邊的靜音鍵走，app 裡不再有開關
    private func recordNode() {
        let isReturn = store.logToday()
        Haptic.thunk()
        SoundPlayer.shared.thunk()
        if isReturn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                Haptic.bloom()
                SoundPlayer.shared.ping()
            }
        }
    }

    private func goSentence(_ target: SettingsTarget?) {
        withAnimation(Feel.transition) { store.openSentence(target) }
    }
}

/// 標題右邊的文字膠囊
struct HeaderPill: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .domyType(Ty.callout)
                .foregroundStyle(Theme.strong)
                .padding(.horizontal, Sp.s4)
                .frame(height: Sz.touch)
                .background(Theme.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(DomyPressStyle())
    }
}

/// 開關句當大標題：如果〔開關〕，／我就〔最小一步〕。句子越長字越小
struct Sentence: View {
    var trigger: String
    var floor: String

    var body: some View {
        let count = trigger.count + floor.count
        let style = count > 48 ? Ty.headline : count > 24 ? Ty.title3 : Ty.title1
        (soft("如果") + strong(trigger) + strong("，\n") + soft("我就") + strong(floor) + strong("。"))
            .font(.system(style.textStyle))
            .lineSpacing(Sp.s1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func soft(_ t: String) -> Text { Text(t).foregroundStyle(Theme.fg2) }
    private func strong(_ t: String) -> Text { Text(t).bold().foregroundStyle(Theme.fg) }
}

/// 挖出來了
struct DugView: View {
    @Environment(Store.self) private var store

    var body: some View {
        DomyScreen(title: "挖出來了", sub: store.today.long) {
            if let p = store.state.justDug {
                VStack(spacing: Sp.s3) {
                    PotatoView(width: 140) // domy-ignore: 插畫尺寸
                        .padding(.vertical, Sp.s4)
                    Text(p.floor)
                        .domyType(Ty.title2)
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                DomyStatGrid(items: [
                    DomyStat(value: "\(p.nodes)", unit: "條", label: "根"),
                    DomyStat(value: "\(p.ret)", unit: "次", label: "回來"),
                    DomyStat(value: "\(p.days)", unit: "天", label: "種了"),
                ])
            }
            DomyInfoStrip(text: "時機、東西擺的位置都留著，只是不用再記了。")
            DomyButton("種下一個" + (store.state.queue.first.map { "：\($0)" } ?? "")) {
                store.plantNext()
            }
        }
    }
}

/// 放手兩週到了，憑感覺回想做了幾天。沒有預設天數（原本停在 12，幾乎一定過關，審查 P0-4）
struct LetGoEndView: View {
    @Environment(Store.self) private var store
    /// nil 還沒選；-1 是「記不清楚」
    @State private var days: Int? = nil

    var body: some View {
        DomyScreen(title: "放手兩週到了", sub: "不用翻紀錄，憑感覺回想就好。") {
            Card {
                CardBody(spacing: Sp.s3) {
                    Text(Copy.t(.p3, ["floor": store.state.habit?.floor ?? ""]))
                        .domyType(Ty.body)
                        .foregroundStyle(Theme.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    DayCountPicker(selection: $days, unsure: Copy.t(.p3unsure))
                }
            }
            DomyButton(days == nil ? Copy.t(.p3disabled) : Copy.t(.p3button), disabled: days == nil) {
                guard let d = days else { return }
                store.finishLetGo(days: d < 0 ? nil : d)
            }
        }
    }
}
