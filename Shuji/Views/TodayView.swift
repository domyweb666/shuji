import SwiftUI

/// 主畫面「今天」。狀態照原型 renderMain 的順序：
/// 挖出來了 → 放手測試 → 停了超過兩週 → 今天做了 → 今天請假 → 還沒做（按住）。
/// 版面（Claude Design 方向 C，QC-0004 多米選的）：日期一行 → 開關句當大標題 → 土面的藤 → 土裡那顆地瓜。
/// 地瓜就是核心大鈕，記好、請假、放手時同一個位置換樣子。要讀的字都在土面上，土裡只有地瓜上的字。
struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.domyBottomInset) private var bottomInset
    @State private var sheet: TodaySheet? = nil
    /// 「這週有被打斷過嗎？」點過就不再出現（記的是哪個習慣，換習慣會重新出現一次）
    @AppStorage("shuji.ai.obstaclePromptSeen") private var obstaclePromptSeen = ""

    /// 土面以上：一片葉子加捲鬚的高度
    private static let vineAbove: CGFloat = 60 // domy-ignore: 插畫畫布高度
    /// 土面到地瓜那一塊：留給根
    private static let rootGap: CGFloat = 76 // domy-ignore: 插畫畫布高度
    /// 地瓜外框上緣到外圈上緣
    private static let ringInset: CGFloat = 20 // domy-ignore: 插畫尺寸

    enum TodaySheet: String, Identifiable {
        case more
        case review
        case tips
        case diagnose
        case obstacle
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
            case .more: MoreSheet()
            case .review: WeekSheet(start: .review)
            case .tips: TipsSheet()
            case .diagnose: DiagnoseSheet()
            case .obstacle: ObstacleSheet()
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
            if store.state.travel { Chip("旅行中") }
            if canOpenMore { MoreButton(label: moreLabel) { sheet = .more } }
        }
        .frame(minHeight: Sz.iconButton)
    }

    /// 昨天忘了記、今天請假、撤銷都收在右上角 ⋯
    private var canOpenMore: Bool {
        store.state.habit != nil && store.state.letgoDaysLeft(today: t) == nil
    }

    private var moreLabel: String {
        store.state.log(on: t) == nil ? "昨天忘了記、今天請假" : "更多選項，可以撤銷今天"
    }

    // MARK: 土面上的字

    @ViewBuilder
    private var words: some View {
        if let h = store.state.habit {
            let log = store.state.log(on: t)
            let floor = store.state.activeFloor
            if let left = store.state.letgoDaysLeft(today: t) {
                Sentence(trigger: h.trigger, floor: floor)
                note("放手測試中，照常做就好，不用記。還有 \(left) 天。")
            } else if store.state.longAbsence(today: t) {
                absence(h)
            } else if let log, log.t == .done {
                Sentence(trigger: h.trigger, floor: floor)
                note(Phrases.phrase(for: t, isReturn: store.state.isReturn(t)))
                // 記好之後最多多出一行：週回顧優先（.analytics/08 安靜規則 2）
                if store.state.reviewPending(today: t) {
                    textLink(t.weekday == store.state.settings.reviewDay ? "今天週回顧 · 開始四問" : "這週的開始四問還沒做") {
                        sheet = .review
                    }
                } else if AIClient.shared.isAvailable && store.state.obstaclePromptReady(today: t) && obstaclePromptSeen != h.planted.string {
                    textLink("這週有被打斷過嗎？") {
                        obstaclePromptSeen = h.planted.string
                        sheet = .obstacle
                    }
                }
            } else if let log, log.t == .leave {
                Sentence(trigger: h.trigger, floor: floor)
                note(["今天請假。", log.reason ?? ""].joined())
            } else {
                Sentence(trigger: h.trigger, floor: floor)
                if store.state.consecutiveMissed(today: t) >= 2 {
                    textLink("卡住的話，看看開關有沒有出現，或最小一步太大") { goSentence(nil) }
                    if !h.backup.isEmpty { note("不順的時候：\(h.backup)") }
                } else if store.state.travelEndedOn == t.adding(-1) {
                    note("回家第一天，東西擺回原位了嗎？")
                }
            }
        }
    }

    @ViewBuilder
    private func absence(_ h: Habit) -> some View {
        Card {
            CardBody {
                Text("藤還在，根都還在。")
                    .domyType(Ty.title3)
                    .foregroundStyle(Theme.fg)
                Text("停了一陣子。接上之前，看一下哪裡卡住：")
                    .domyType(Ty.subheadline)
                    .foregroundStyle(Theme.fg2)
            }
        }
        if !h.why.isEmpty {
            Card {
                CardBody(spacing: Sp.s1) {
                    Eyebrow("你說這是為了")
                    Text(h.why).domyType(Ty.body).foregroundStyle(Theme.fg)
                }
            }
        }
        VStack(spacing: Sp.s2) {
            Card {
                RowButton(text: "開關有出現嗎？") { goSentence(.trigger) }
                RowSep()
                RowButton(text: "最小一步太大嗎？") { goSentence(.floor) }
                RowSep()
                RowButton(text: "旁邊有更近的東西搶走了嗎？") { sheet = .tips }
            }
            if AIClient.shared.isAvailable {
                DomyButton("回答三題，幫我找哪裡要改", variant: .plain, size: .compact, fullWidth: true) { sheet = .diagnose }
            }
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
    }

    // MARK: 土

    /// 藤、土和地瓜。地瓜底下讓出分頁列
    private var soil: some View {
        let box = PotatoBody<EmptyView>.frameSize.height
        let top = TodayView.vineAbove + TodayView.rootGap
        return VineView(soilTop: TodayView.vineAbove, potatoTop: top + TodayView.ringInset)
            .frame(height: top + box + Sp.s2 + bottomInset)
            .overlay(alignment: .top) {
                potato
                    .padding(.top, top)
                    .animation(Feel.transition, value: store.state.log(on: t)?.t)
            }
    }

    @ViewBuilder
    private var potato: some View {
        let log = store.state.log(on: t)
        if store.state.letgoDaysLeft(today: t) != nil {
            PotatoSeal(icon: "hourglass", title: "放手中", style: .quiet)
        } else if let log, log.t == .done {
            PotatoSeal(icon: "checkmark", title: "記好了", style: .done)
        } else if let log, log.t == .leave {
            PotatoSeal(icon: "moon.zzz", title: "請假", style: .quiet)
        } else {
            HoldButton(hint: store.state.longAbsence(today: t) ? "從這一節接上" : "做完最小一步，按住一下") { recordNode() }
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

/// 標題右邊的 ⋯
struct MoreButton: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(Ty.headline.font)
                .foregroundStyle(Theme.fg)
                .frame(width: Sz.iconButton, height: Sz.iconButton)
                .background(Theme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(DomyPressStyle())
        .accessibilityLabel(label)
    }
}

/// 開關句當大標題：如果〔開關〕，／我就〔最小一步〕。句子長就小一級
struct Sentence: View {
    var trigger: String
    var floor: String

    var body: some View {
        let style = trigger.count + floor.count > 24 ? Ty.title3 : Ty.title1
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
            DomyInfoStrip(text: "開關、東西擺的位置都留著，只是不用再記了。")
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
