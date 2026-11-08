import SwiftUI

/// 主畫面「今天」。狀態照原型 renderMain 的順序：
/// 挖出來了 → 放手測試 → 停了超過兩週 → 今天做了 → 今天請假 → 還沒做（按住）。
struct TodayView: View {
    @Environment(Store.self) private var store
    @State private var sheet: TodaySheet? = nil
    /// 「這週有被打斷過嗎？」點過就不再出現（記的是哪個習慣，換習慣會重新出現一次）
    @AppStorage("shuji.ai.obstaclePromptSeen") private var obstaclePromptSeen = ""

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
            case .review: ReviewSheet()
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
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        stateBody
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 560)
                    .padding(.top, 44)
                    Spacer(minLength: 8)
                    VineView()
                        .frame(height: 230)
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        let st = store.state.stats(today: t)
        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今天").font(.largeTitle.weight(.bold))
                Text("\(t.long) · 第 \(st.nodes) 節").font(.body).foregroundStyle(Theme.fg2)
            }
            Spacer()
            if store.state.travel { Chip("旅行中") }
        }
    }

    @ViewBuilder
    private var stateBody: some View {
        if let h = store.state.habit {
            let log = store.state.log(on: t)
            let floor = store.state.activeFloor
            if let left = store.state.letgoDaysLeft(today: t) {
                SwitchCard(trigger: h.trigger, floor: floor).padding(.top, 18)
                VStack(spacing: 10) {
                    Text("放手測試中，照常做就好，不用記。")
                        .multilineTextAlignment(.center)
                        .padding(.top, 30)
                    Text("還有 \(left) 天").font(.subheadline).foregroundStyle(Theme.fg2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .frame(minHeight: 190)
            } else if store.state.longAbsence(today: t) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("藤還在，根都還在。").font(.system(size: 20)).lineSpacing(5)
                        Text("停了一陣子。接上之前，看一下哪裡卡住：").font(.subheadline).foregroundStyle(Theme.fg2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 20, leading: 20, bottom: 22, trailing: 20))
                }
                .padding(.top, 18)
                if !h.why.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("你說這是為了").font(.footnote).foregroundStyle(Theme.fg2)
                            Text(h.why)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
                    }
                    .padding(.top, 14)
                }
                Card {
                    RowButton(text: "開關有出現嗎？") { goSettings(.trigger) }
                    RowSep()
                    RowButton(text: "最小一步太大嗎？") { goSettings(.floor) }
                    RowSep()
                    RowButton(text: "旁邊有更近的東西搶走了嗎？") { sheet = .tips }
                }
                .padding(.top, 14)
                if AIClient.shared.isAvailable {
                    LinkButton(title: "回答三題，幫我找哪裡要改 ›") { sheet = .diagnose }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                holdBlock(hint: "從這一節接上，按住")
            } else if let log, log.t == .done {
                SwitchCard(trigger: h.trigger, floor: floor, dim: true).padding(.top, 18)
                VStack(spacing: 10) {
                    Text(Phrases.phrase(for: t, isReturn: store.state.isReturn(t)))
                        .multilineTextAlignment(.center)
                        .padding(.top, 26)
                    Button { sheet = .more } label: {
                        HStack(spacing: 6) {
                            Text("今天記好了")
                            Text("⋯").accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.fg2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Theme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("今天記好了，更多選項")
                    if AIClient.shared.isAvailable && store.state.obstaclePromptReady(today: t) && obstaclePromptSeen != h.planted.string {
                        LinkButton(title: "這週有被打斷過嗎？ ›") {
                            obstaclePromptSeen = h.planted.string
                            sheet = .obstacle
                        }
                    }
                    if store.state.reviewPending(today: t) {
                        LinkButton(title: t.weekday == store.state.settings.reviewDay ? "今天週回顧 · 開始四問 ›" : "這週的開始四問還沒做 ›") { sheet = .review }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .frame(minHeight: 190)
            } else if let log, log.t == .leave {
                SwitchCard(trigger: h.trigger, floor: floor, dim: true).padding(.top, 18)
                VStack(spacing: 10) {
                    Text("今天請假。").padding(.top, 26)
                    Text(log.reason ?? "").font(.subheadline).foregroundStyle(Theme.fg2)
                    Button { sheet = .more } label: {
                        HStack(spacing: 6) {
                            Text("今天請假了")
                            Text("⋯").accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.fg2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Theme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("今天請假了，更多選項")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                .frame(minHeight: 190)
            } else {
                SwitchCard(trigger: h.trigger, floor: floor).padding(.top, 18)
                let missed = store.state.consecutiveMissed(today: t)
                let cameHome = store.state.travelEndedOn == t.adding(-1)
                holdBlock(hint: "做完最小一步，按住一下") {
                    if missed >= 2 {
                        LinkButton(title: "卡住的話，看看開關有沒有出現，或最小一步太大 ›") { goSettings(nil) }
                        if !h.backup.isEmpty {
                            Text("不順的時候：\(h.backup)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.fg2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                    } else if cameHome {
                        Text("回家第一天，東西擺回原位了嗎？")
                            .font(.subheadline)
                            .foregroundStyle(Theme.fg2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
    }

    private func holdBlock(hint: String) -> some View {
        holdBlock(hint: hint) { EmptyView() }
    }

    private func holdBlock<Extra: View>(hint: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 10) {
            HoldButton(hint: hint) { recordNode() }
            extra()
            LinkButton(title: "昨天忘了記 · 今天請假", quiet: true) { sheet = .more }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .frame(minHeight: 190)
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

    private func goSettings(_ target: SettingsTarget?) {
        store.settingsTarget = target
        withAnimation(.easeInOut(duration: 0.38)) { store.page = 2 }
    }
}

/// 挖出來了
struct DugView: View {
    @Environment(Store.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BigTitle(title: "挖出來了", sub: store.today.long)
                if let p = store.state.justDug {
                    Card {
                        VStack(spacing: 8) {
                            PotatoView(width: 120)
                            Text(p.floor).font(.title2.weight(.bold)).multilineTextAlignment(.center).padding(.top, 8)
                            Text("\(p.nodes) 條根 · 回來 \(p.ret) 次 · 種了 \(p.days) 天")
                                .font(.subheadline).foregroundStyle(Theme.fg2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(EdgeInsets(top: 20, leading: 20, bottom: 22, trailing: 20))
                    }
                }
                Card {
                    Text("開關、東西擺的位置都留著，只是不用再記了。")
                        .font(.subheadline).foregroundStyle(Theme.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
                }
                PrimaryButton(title: "種下一個" + (store.state.queue.first.map { "：\($0)" } ?? "")) {
                    store.plantNext()
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 560)
            .padding(.top, 44)
            .padding(.bottom, 40)
        }
    }
}

/// 放手兩週到了，憑感覺回想做了幾天
struct LetGoEndView: View {
    @Environment(Store.self) private var store
    @State private var days: Double = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BigTitle(title: "放手兩週到了", sub: "不用翻紀錄，憑感覺回想就好。")
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("這兩週，大概有幾天做了「\(store.state.habit?.floor ?? "")」？")
                            .font(.system(size: 16)).lineSpacing(4)
                        Slider(value: $days, in: 0...14, step: 1).tint(Theme.accent)
                        HStack {
                            Text("0 天")
                            Spacer()
                            Text("\(Int(days)) 天").foregroundStyle(Theme.fg).fontWeight(.semibold)
                            Spacer()
                            Text("14 天")
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.fg2)
                    }
                    .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
                }
                PrimaryButton(title: "記下來") { store.finishLetGo(days: Int(days)) }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 560)
            .padding(.top, 44)
            .padding(.bottom, 40)
        }
    }
}
