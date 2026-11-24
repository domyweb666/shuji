import SwiftUI

/// 主畫面「今天」。狀態照原型 renderMain 的順序：
/// 挖出來了 → 放手測試 → 停了超過兩週 → 今天做了 → 今天請假 → 還沒做（按住）。
/// 版面：大標題 → 開關句卡 → 核心大鈕（或今天的狀態章）→ 地瓜藤。大鈕和狀態章在同一個位置，形狀跟著狀態換。
struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.domyBottomInset) private var bottomInset
    @State private var sheet: TodaySheet? = nil
    /// 「這週有被打斷過嗎？」點過就不再出現（記的是哪個習慣，換習慣會重新出現一次）
    @AppStorage("shuji.ai.obstaclePromptSeen") private var obstaclePromptSeen = ""

    /// 土面以上：一片葉子加捲鬚的高度
    private static let vineAbove: CGFloat = 60 // domy-ignore: 插畫畫布高度
    /// 土面到讓位線（分頁列上緣再上去 16）：根最長 74，整條露在分頁列上面
    private static let vineBelow: CGFloat = 64 // domy-ignore: 插畫畫布高度

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
                    VStack(alignment: .leading, spacing: Sp.s6) {
                        header
                        stateBody
                    }
                    // 按滿、請假、撤銷：大鈕和狀態章淡入淡出換場，不要瞬間跳
                    .animation(Feel.transition, value: store.state.log(on: t)?.t)
                    .padding(.horizontal, Sz.screenMargin)
                    .padding(.top, Theme.pageTop)
                    .frame(maxWidth: Theme.contentMaxWidth)
                    Spacer(minLength: Sp.s2)
                    // 藤往下多長一段，讓分頁列浮在土上，不蓋到葉子
                    VineView(soilDepth: TodayView.vineBelow + bottomInset)
                        .frame(height: TodayView.vineAbove + TodayView.vineBelow + bottomInset)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.canvas)
    }

    private var header: some View {
        let st = store.state.stats(today: t)
        return DomyHeader(title: "今天", sub: GlanceCopy.todaySub(date: t.long, nodes: st.nodes)) {
            HStack(spacing: Sp.s2) {
                if store.state.travel { Chip("旅行中") }
                if canOpenMore { MoreButton { sheet = .more } }
            }
        }
    }

    /// 還沒記的時候，昨天忘了記、今天請假收在右上角。記好之後走狀態章下面那顆膠囊
    private var canOpenMore: Bool {
        store.state.habit != nil && store.state.log(on: t) == nil && store.state.letgoDaysLeft(today: t) == nil
    }

    @ViewBuilder
    private var stateBody: some View {
        if let h = store.state.habit {
            let log = store.state.log(on: t)
            let floor = store.state.activeFloor
            if let left = store.state.letgoDaysLeft(today: t) {
                SwitchCard(trigger: h.trigger, floor: floor)
                stage {
                    StatusSeal(icon: "hourglass", title: "放手中", style: .quiet)
                    Text("放手測試中，照常做就好，不用記。")
                        .domyType(Ty.body)
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.center)
                    Text("還有 \(left) 天").domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
                }
            } else if store.state.longAbsence(today: t) {
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
                holdBlock(hint: "從這一節接上，按住")
            } else if let log, log.t == .done {
                SwitchCard(trigger: h.trigger, floor: floor, dim: true)
                stage {
                    StatusSeal(icon: "checkmark", title: "記好了", style: .done)
                    Text(Phrases.phrase(for: t, isReturn: store.state.isReturn(t)))
                        .domyType(Ty.body)
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.center)
                    MoreCapsule(title: "今天記好了") { sheet = .more }
                    // 記好之後最多多出一行：週回顧優先（.analytics/08 安靜規則 2）
                    if store.state.reviewPending(today: t) {
                        DomyButton(t.weekday == store.state.settings.reviewDay ? "今天週回顧 · 開始四問" : "這週的開始四問還沒做",
                                   variant: .plain, size: .compact) { sheet = .review }
                    } else if AIClient.shared.isAvailable && store.state.obstaclePromptReady(today: t) && obstaclePromptSeen != h.planted.string {
                        DomyButton("這週有被打斷過嗎？", variant: .plain, size: .compact) {
                            obstaclePromptSeen = h.planted.string
                            sheet = .obstacle
                        }
                    }
                }
            } else if let log, log.t == .leave {
                SwitchCard(trigger: h.trigger, floor: floor, dim: true)
                stage {
                    StatusSeal(icon: "moon.zzz", title: "請假", style: .quiet)
                    Text("今天請假。").domyType(Ty.body).foregroundStyle(Theme.fg)
                    if let reason = log.reason, !reason.isEmpty {
                        Text(reason).domyType(Ty.subheadline).foregroundStyle(Theme.fg2)
                    }
                    MoreCapsule(title: "今天請假了") { sheet = .more }
                }
            } else {
                SwitchCard(trigger: h.trigger, floor: floor)
                let missed = store.state.consecutiveMissed(today: t)
                let cameHome = store.state.travelEndedOn == t.adding(-1)
                holdBlock(hint: "做完最小一步，按住一下", showsHint: false) {
                    if missed >= 2 {
                        DomyButton("卡住的話，看看開關有沒有出現，或最小一步太大", variant: .plain, size: .compact, fullWidth: true) {
                            goSentence(nil)
                        }
                        if !h.backup.isEmpty {
                            DomyInfoStrip(text: "不順的時候：\(h.backup)")
                        }
                    } else if cameHome {
                        DomyInfoStrip(text: "回家第一天，東西擺回原位了嗎？")
                    }
                }
            }
        }
    }

    /// 大鈕那一塊：置中，最小高度固定，換狀態時版面不跳
    private func stage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Sp.s3) { content() }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Sz.heroRing)
    }

    private func holdBlock(hint: String) -> some View {
        holdBlock(hint: hint) { EmptyView() }
    }

    private func holdBlock<Extra: View>(hint: String, showsHint: Bool = true, @ViewBuilder extra: () -> Extra) -> some View {
        stage {
            HoldButton(hint: hint, showsHint: showsHint) { recordNode() }
            extra()
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
        .accessibilityLabel("昨天忘了記、今天請假")
    }
}

/// 今天的狀態章：佔核心大鈕的位置，記好了是產品色實心，請假、放手是安靜的淡色
struct StatusSeal: View {
    enum Style { case done, quiet }

    var icon: String
    var title: String
    var style: Style

    var body: some View {
        let done = style == .done
        ZStack {
            Circle().strokeBorder(done ? Theme.accent : Theme.soft, lineWidth: Sz.heroRingWidth)
            Circle()
                .fill(done ? Theme.accent : Theme.tint)
                .frame(width: Sz.heroButton, height: Sz.heroButton)
                .overlay {
                    VStack(spacing: Sp.s1) {
                        Image(systemName: icon).font(Ty.title1.font)
                        Text(title).domyType(Ty.headline)
                    }
                    .foregroundStyle(done ? Theme.onAccent : Theme.strong)
                }
        }
        .frame(width: Sz.heroRing, height: Sz.heroRing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// 「今天記好了 ⋯」那顆灰膠囊，點了開更多選項
struct MoreCapsule: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Sp.s2) {
                Text(title).domyType(Ty.callout)
                Image(systemName: "ellipsis").font(Ty.callout.font).accessibilityHidden(true)
            }
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, Sp.s4)
            .frame(height: Sz.buttonCompact)
            .background(Theme.surfaceMuted, in: Capsule())
            .frame(minHeight: Sz.touch)
            .contentShape(Capsule())
        }
        .buttonStyle(DomyPressStyle())
        .accessibilityLabel("\(title)，更多選項")
    }
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
