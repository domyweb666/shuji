import SwiftUI

// 跟地瓜對答（任務 8）：首次設定、重新規劃、想下一個要種什麼都用這一頁。
// 一頁一題，AI 直接給答案，人只要點；都不是才自己打。樣子照畫布 Talk、ChatWait。

struct TalkView: View {
    @Environment(Store.self) private var store
    @Bindable var model: TalkModel
    /// 只挑最小一步放進排隊，不種、不碰現在的習慣
    var queueOnly = false
    /// 第一步按返回要去哪；nil 是沒地方回（首次設定）
    var onExit: (() -> Void)? = nil
    /// 改成自己填那兩格。排隊不用（它只要一句，在這頁打）
    var onManual: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    /// 種好了（排隊：排好了）
    var onDone: () -> Void

    @State private var connecting = false
    /// 沒連電腦就按了送出：連上之後接著送
    @State private var sendAfterConnect = false
    @FocusState private var writing: Bool
    @AccessibilityFocusState private var reading: Bool
    private let ai = AIClient.shared

    private static let inputID = "input"
    private static let potato: CGFloat = 150 // domy-ignore: 插畫尺寸
    private static let potatoBig: CGFloat = 180 // domy-ignore: 插畫尺寸
    private static let barHeight = Sp.s1 + Sp.s1 / 2
    private static let optionHeight = Sz.button + Sp.s2
    private static let inputHeight = Sz.button + Sp.s1

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                ScrollViewReader { reader in
                    ScrollView {
                        Group {
                            if model.phase == .waiting { waiting } else { talk }
                        }
                        .padding(.horizontal, Sz.screenMargin)
                        .padding(.bottom, Sp.s6)
                        .frame(maxWidth: Theme.contentMaxWidth)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture { writing = false }
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    // 鍵盤升起來之後，輸入框整條露出來
                    .onChange(of: geo.size.height) { _, _ in
                        guard writing else { return }
                        withAnimation(Feel.transition) { reader.scrollTo(TalkView.inputID, anchor: UnitPoint(x: 0.5, y: 0.96)) }
                    }
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .animation(Feel.transition, value: screen)
        .onChange(of: screen) { _, _ in moveReading() }
        .onChange(of: ai.isAvailable) { _, on in
            if on { connecting = false }
        }
        .sheet(isPresented: $model.needsConsent, onDismiss: { model.decline() }) {
            AIConsentSheet(agree: { model.agree() }, decline: { model.decline() })
        }
        .sheet(isPresented: $connecting, onDismiss: { connectClosed() }) { connectSheet }
    }

    // MARK: 上面那一排

    private var topBar: some View {
        HStack(spacing: Sp.s4) {
            if canGoBack {
                Button {
                    writing = false
                    if !model.back() { onExit?() }
                } label: {
                    circleLabel("chevron.left")
                }
                .buttonStyle(DomyPressStyle())
                .accessibilityLabel("上一步")
            } else {
                cornerSpace
            }
            progress
            corner
        }
        .padding(.horizontal, Sz.screenMargin)
        .padding(.vertical, Sp.s2)
        .frame(maxWidth: Theme.contentMaxWidth)
    }

    private var canGoBack: Bool {
        model.step != .goal || model.phase != .ready || onExit != nil
    }

    private var total: Int { queueOnly ? 2 : 4 }
    private var shownStep: Int { min(model.step.rawValue, total) }

    private var progress: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceMuted)
                Capsule()
                    .fill(Theme.leafDynamic)
                    .frame(width: geo.size.width * CGFloat(min(model.answered, total)) / CGFloat(total))
            }
        }
        .frame(height: TalkView.barHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(shownStep) 步，共 \(total) 步")
    }

    /// 第一步的右上角：自己填、從備份還原都收在這裡
    @ViewBuilder
    private var corner: some View {
        if model.step == .goal, model.phase == .ready, let onRestore {
            Menu {
                Button("自己填") { manual() }
                Button("從備份還原") { onRestore() }
            } label: {
                circleLabel("ellipsis")
            }
            .accessibilityLabel("更多")
        } else {
            cornerSpace
        }
    }

    private var cornerSpace: some View {
        Color.clear.frame(width: Sz.touch, height: Sz.touch)
    }

    private func circleLabel(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(Ty.headline.font)
            .foregroundStyle(Theme.fg)
            .frame(width: Sz.touch, height: Sz.touch)
            .background(Theme.surface, in: Circle())
            .contentShape(Circle())
    }

    // MARK: 對答

    private var talk: some View {
        VStack(spacing: Sp.s4) {
            TalkPotato(width: TalkView.potato)
                .padding(.top, Sp.s2)
            if let said = model.bubble { bubble(said) }
            card
            Spacer(minLength: Sp.s2)
            controls
        }
    }

    private func bubble(_ text: String) -> some View {
        Text(text)
            .domyType(Ty.body)
            .foregroundStyle(Theme.strong)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Sp.s4)
            .padding(.vertical, Sp.s3)
            .background(Theme.soft, in: RoundedRectangle(cornerRadius: Rd.xxl, style: .continuous))
            .padding(.leading, Sp.s12)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("你說：\(text)")
    }

    @ViewBuilder
    private var card: some View {
        switch model.phase {
        case .unfit(let referral):
            ReferralCard(text: referral)
                .accessibilityFocused($reading)
        case .failed(let message):
            let parts = TalkView.split(message)
            cardBox {
                big(parts.first, style: Ty.title1)
                if !parts.rest.isEmpty { small(parts.rest) }
            }
        case .ready, .waiting:
            cardBox {
                small(words.lead)
                big(words.big, style: Ty.title1)
                if !words.foot.isEmpty { small(words.foot) }
            }
        }
    }

    /// 第一句放大，其他的是怎麼辦
    private static func split(_ message: String) -> (first: String, rest: String) {
        guard let dot = message.firstIndex(of: "。") else { return (message, "") }
        return (String(message[..<dot]), String(message[message.index(after: dot)...]))
    }

    private func cardBox<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Sp.s2) { content() }
            .padding(Sp.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Rd.xxl, style: .continuous))
    }

    private func small(_ text: String) -> some View {
        Text(text)
            .domyType(Ty.body)
            .foregroundStyle(Theme.fg2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func big(_ text: String, style: DomyTypeStyle) -> some View {
        Text(text)
            .domyType(style)
            .foregroundStyle(Theme.fg)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($reading)
    }

    private struct Words {
        var lead: String
        var big: String
        var foot: String
    }

    private var words: Words {
        switch model.step {
        case .goal:
            return Words(lead: model.offTopic == nil ? "我是地瓜。" : "這個我不會，我只懂養習慣。",
                         big: "你想養成什麼？", foot: "")
        case .floor:
            return Words(lead: model.floorOffer.lead.isEmpty ? "最累那天也做得到的是？" : model.floorOffer.lead,
                         big: model.showsInput ? "打一個最小的" : "挑一個最小的", foot: "")
        case .trigger:
            return Words(lead: model.triggerOffer.lead.isEmpty ? "每天一定會做的是？" : model.triggerOffer.lead,
                         big: "接在它後面", foot: "")
        case .plan:
            let n = model.days ?? HabitDifficulty.medium.days
            return Words(lead: "\(model.trigger)，就\(model.floor)。", big: "預估 \(n) 天",
                         foot: TalkModel.dueLine(today: store.today, days: n))
        }
    }

    // MARK: 下面那一區

    private var controls: some View {
        VStack(spacing: Sp.s3) {
            switch model.phase {
            case .unfit:
                DomyButton("換一件事", variant: .secondary) { model.restart() }
            case .failed:
                DomyButton("再試一次") { model.retry() }
                DomyButton(queueOnly ? "自己打" : "自己填", variant: .plain) { manual() }
            case .ready, .waiting:
                stepControls
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var stepControls: some View {
        switch model.step {
        case .goal:
            goalControls
        case .floor, .trigger:
            pickControls
        case .plan:
            option("種下去", primary: true) { plant() }
        }
    }

    @ViewBuilder
    private var goalControls: some View {
        if model.showsInput {
            inputRow
            if !ai.isAvailable, !writing {
                DomyButton("連電腦的 Claude", variant: .secondary) { connecting = true }
                DomyButton(queueOnly ? "自己打" : "自己填", variant: .plain) { manual() }
            }
        } else {
            ForEach(TalkModel.presets, id: \.self) { p in
                option(p) { send(p) }
            }
            DomyButton("自己打", variant: .plain) { typeOwn() }
        }
    }

    @ViewBuilder
    private var pickControls: some View {
        // 自己打的時候收起選項，鍵盤才不會蓋住輸入框；上一步就回到選項
        if model.showsInput {
            if model.draftNegative {
                WarnBox { Text(Wording.negativeWarning) }
            }
            inputRow
        } else {
            ForEach(model.offer.options, id: \.self) { o in
                option(o) { pick(o) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Sp.s5) { pickLinks }
                VStack(spacing: 0) { pickLinks }
            }
        }
    }

    @ViewBuilder
    private var pickLinks: some View {
        // 字寬進位會少不到 1 點，「換一批」就折成兩行：鎖一行，差那一點用縮字補
        Group {
            DomyButton("換一批", variant: .plain) { model.more() }
            DomyButton("都不是，自己打", variant: .plain) { typeOwn() }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }

    private func option(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Rd.xxl, style: .continuous)
        return Button {
            Haptic.select()
            action()
        } label: {
            Text(title)
                .domyType(Ty.headline)
                .foregroundStyle(primary ? Theme.onAccent : Theme.fg)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Sp.s5)
                .padding(.vertical, Sp.s3)
                .frame(maxWidth: .infinity, minHeight: TalkView.optionHeight)
                .background(primary ? Theme.accent : Theme.surface, in: shape)
                .contentShape(shape)
        }
        .buttonStyle(DomyPressStyle())
    }

    private var inputRow: some View {
        HStack(spacing: Sp.s2) {
            TextField("寫在這裡", text: $model.draft)
                .focused($writing)
                .submitLabel(.send)
                .autocorrectionDisabled()
                .onSubmit { sendDraft() }
                .onChange(of: model.draft) { _, v in
                    if v.count > model.draftLimit { model.draft = String(v.prefix(model.draftLimit)) }
                }
                .domyType(Ty.body)
                .foregroundStyle(Theme.fg)
                .tint(Theme.accent)
                .padding(.horizontal, Sp.s5)
                .frame(minHeight: TalkView.inputHeight)
                .background(Theme.surface, in: Capsule())
                .accessibilityLabel(words.big)
            Button { sendDraft() } label: {
                Image(systemName: "arrow.up")
                    .font(Ty.title3.font)
                    .foregroundStyle(model.canSend ? Theme.onAccent : Theme.disabled)
                    .frame(width: TalkView.inputHeight, height: TalkView.inputHeight)
                    .background(model.canSend ? Theme.accent : Theme.surfaceMuted, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(DomyPressStyle())
            .disabled(!model.canSend)
            .accessibilityLabel("送出")
        }
        .id(TalkView.inputID)
    }

    // MARK: 等 AI

    private var waiting: some View {
        VStack(spacing: Sp.s6) {
            Spacer(minLength: Sp.s6)
            TalkPotato(width: TalkView.potatoBig, thinking: true)
            Text(waitingText)
                .domyType(Ty.title3)
                .fontWeight(.bold)
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($reading)
            DomyButton(queueOnly ? "不等了，自己打" : "不等了，自己填", variant: .plain) { manual() }
            Spacer(minLength: Sp.s12)
        }
        .frame(maxWidth: .infinity)
    }

    private var waitingText: String {
        switch model.step {
        case .goal, .floor: return "在想最小的一步"
        case .trigger: return "在想接在哪裡"
        case .plan: return "在算要多久"
        }
    }

    // MARK: 連電腦

    private var connectSheet: some View {
        NavigationStack {
            AIHubView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("關閉") { connecting = false }
                    }
                }
        }
        .environment(\.domyBottomInset, Sp.s8)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
        .tint(Theme.accent)
    }

    private func connectClosed() {
        let go = sendAfterConnect
        sendAfterConnect = false
        if go, ai.isAvailable { sendDraft() }
    }

    // MARK: 動作

    private func sendDraft() {
        guard model.canSend else { return }
        writing = false
        switch model.step {
        case .goal: send(model.draftValue)
        case .floor, .trigger: pick(model.draftValue)
        case .plan: break
        }
    }

    private func send(_ goal: String) {
        writing = false
        guard ai.isAvailable else {
            // 打的字留著，連上之後接著送
            model.draft = goal
            sendAfterConnect = true
            connecting = true
            return
        }
        model.submitGoal(goal)
    }

    private func pick(_ text: String) {
        if model.step == .trigger {
            model.pickTrigger(text)
        } else if queueOnly {
            store.addQueue(TalkModel.clip(text, PlanInput.floorLimit))
            store.show("排進去了。")
            onDone()
        } else {
            model.pickFloor(text)
        }
    }

    private func typeOwn() {
        model.typeOwn()
        focusSoon()
    }

    private func manual() {
        writing = false
        if queueOnly {
            model.ownFloor()
            focusSoon()
        } else {
            model.leave()
            onManual?()
        }
    }

    /// 等輸入框畫好再給焦點
    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { writing = true }
    }

    private func plant() {
        guard let days = model.days, !model.floor.isEmpty, !model.trigger.isEmpty else { return }
        Haptic.bloom()
        // 先拿掉排隊那一句，再種（種下去畫面就換掉了）
        store.removeQueue(model.goal)
        store.plant(floor: model.floor, trigger: model.trigger, estimatedDays: days)
        onDone()
    }

    // MARK: 旁白

    /// 換了一頁就變，旁白移到新的大字
    private var screen: String {
        let kind: String
        switch model.phase {
        case .ready: kind = "ready"
        case .waiting: kind = "waiting"
        case .failed: kind = "failed"
        case .unfit: kind = "unfit"
        }
        return "\(model.step.rawValue)|\(kind)|\(model.offTopicCount)|\(model.offer.options.first ?? "")"
    }

    private func moveReading() {
        reading = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { reading = true }
    }
}

/// 有眼睛的地瓜。thinking：眼睛變三個點輪流亮，開了「減少動態」就停著不動
struct TalkPotato: View {
    var width: CGFloat
    var thinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let beat = 0.4

    var body: some View {
        Group {
            if thinking && !reduceMotion {
                TimelineView(.periodic(from: .now, by: TalkPotato.beat)) { context in
                    drawing(lit: Int(context.date.timeIntervalSinceReferenceDate / TalkPotato.beat) % 3)
                }
            } else {
                drawing(lit: nil)
            }
        }
        .frame(width: width, height: width * 130 / 180)
        .accessibilityHidden(true)
    }

    private func dotOpacity(_ i: Int, lit: Int?) -> Double {
        if let lit { return lit == i ? 1 : 0.4 }
        return [1.0, 0.7, 0.4][i]
    }

    /// 座標照畫布的 SVG：寬 180 高 130，原點在地瓜中間
    private func drawing(lit: Int?) -> some View {
        Canvas { ctx, size in
            var g = ctx
            g.scaleBy(x: size.width / 180, y: size.width / 180)
            g.translateBy(x: 90, y: 65)

            if !thinking {
                var vine = Path()
                vine.move(to: CGPoint(x: 0, y: -44))
                vine.addQuadCurve(to: CGPoint(x: 18, y: -60), control: CGPoint(x: 4, y: -58))
                g.stroke(vine, with: .color(Theme.vineDynamic), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                var leaf = Path()
                leaf.move(to: CGPoint(x: 18, y: -60))
                leaf.addCurve(to: CGPoint(x: 34, y: -50), control1: CGPoint(x: 30, y: -68), control2: CGPoint(x: 42, y: -58))
                leaf.addCurve(to: CGPoint(x: 18, y: -60), control1: CGPoint(x: 28, y: -44), control2: CGPoint(x: 20, y: -50))
                leaf.closeSubpath()
                g.fill(leaf, with: .color(Theme.leafDynamic))
            }

            var skin = g
            skin.rotate(by: .degrees(-8))
            skin.fill(Path(ellipseIn: CGRect(x: -78, y: -45, width: 156, height: 90)), with: .color(Theme.accent))
            skin.fill(Path(ellipseIn: CGRect(x: -56, y: -31, width: 56, height: 18)), with: .color(.white.opacity(0.18)))

            // 眼睛的顏色跟著壓在產品色上的字色走，深色的淺地瓜上才看得到
            if thinking {
                for i in 0..<3 {
                    let dot = CGRect(x: CGFloat(i - 1) * 24 - 5, y: -5, width: 10, height: 10)
                    g.fill(Path(ellipseIn: dot), with: .color(Theme.onAccent.opacity(dotOpacity(i, lit: lit))))
                }
            } else {
                for p in [CGPoint(x: -18, y: 0), CGPoint(x: 22, y: -4)] {
                    let eye = CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
                    g.fill(Path(ellipseIn: eye), with: .color(Theme.onAccent))
                }
            }
        }
    }
}
