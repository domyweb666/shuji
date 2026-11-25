import SwiftUI

/// 週回顧：開始四問 → 週報（WeekVineView）。
/// 時間到了打開 app 自動跳出來（AutoAsk），田裡沒有入口。
struct WeekSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var report: WeekReport? = nil

    var body: some View {
        if let report {
            WeekVineView(report: report, close: { dismiss() }, fake: fakeReply)
        } else {
            ReviewQuestions(onSubmit: submitted, later: { dismiss() })
        }
    }

    private func submitted(_ scores: [Double]) {
        store.recordReview(scores: scores)
        if store.state.settings.weekCard, let r = store.openReport(from: "review") {
            withAnimation(Feel.transition) { report = r }
        } else {
            store.show(Copy.t(.done))
            dismiss()
        }
    }

    private var fakeReply: WeekReviewOutput? {
        #if DEBUG
        return WeekDemo.on ? WeekDemo.reply : nil
        #else
        return nil
        #endif
    }
}

#if DEBUG
/// 啟動參數 -weekDemo：週報用假的 AI 回覆（tools/limrun/week.mjs 拍圖用）。
/// 這個 view 直接就是那一頁，用自己的假存檔，不碰真的。
@MainActor
struct WeekDemo: View {
    static var on: Bool { ProcessInfo.processInfo.arguments.contains("-weekDemo") }

    static var reply: WeekReviewOutput {
        WeekReviewOutput(type: "ok", finding: "漏的都在週末。",
                         change: WeekReviewOutput.Change(field: "backup", label: "下週六日改成", text: "起床就坐上去"))
    }

    @State private var store = WeekDemo.demoStore()

    var body: some View {
        if let report = store.state.weekReport(today: store.today) {
            WeekVineView(report: report, close: {}, fake: WeekDemo.reply)
                .environment(store)
        }
    }

    /// 種到第 3 週，平日做、週末漏
    private static func demoStore() -> Store {
        let s = Store(fileURL: nil, backupDir: nil)
        let end = s.state.lastReviewDay(today: s.today)
        var logs: [String: [String: String]] = [:]
        for i in 0..<21 {
            let d = end.adding(i - 20)
            if d.weekday != 0 && d.weekday != 6 { logs[d.string] = ["t": "done"] }
        }
        let habit: [String: Any] = ["floor": "坐上蒲團", "trigger": "刷完牙", "planted": end.adding(-20).string, "estimatedDays": 60]
        let json: [String: Any] = ["habit": habit, "logs": logs]
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let state = try? JSONDecoder().decode(AppState.self, from: data) {
            s.state = state
        }
        return s
    }
}
#endif

/// 打開 app 自動跳出來的那一張
struct AskSheet: View {
    var ask: AutoAsk
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch ask {
        case .back:
            BackSheet(gap: store.state.pendingGap(today: store.today) ?? PendingGap(from: store.today, to: store.today))
        case .review:
            WeekSheet()
        case .dig:
            AskCard(potato: true, title: "「\(floor)」長好了", yes: "挖地瓜", no: "再種一陣子", onYes: {
                Haptic.bloom()
                dismiss()
                store.route = []
                store.dig()
            }, onNo: { dismiss() })
        case .pressure:
            AskCard(title: "最近有特別忙或累的一週嗎？那週也照做了嗎？", yes: "有，照做了", no: "還沒遇到，或那週掉了", onYes: {
                store.setPressure(true)
                dismiss()
            }, onNo: {
                store.setPressure(false)
                dismiss()
            })
        case .letgo:
            AskCard(title: "試試看，接下來兩週照常做，不用記", yes: "試兩週", no: "先不要", onYes: {
                store.startLetGo()
                dismiss()
            }, onNo: { dismiss() })
        case .remindOff:
            AskCard(potato: true, title: "你已經不需要我提醒了", yes: "好", no: "繼續提醒", onYes: {
                store.stopReminder()
                dismiss()
            }, onNo: { dismiss() })
        case .remindOn:
            AskCard(title: "要不要再提醒你一陣子？", yes: "好", no: "不用", onYes: {
                let s = store
                Task {
                    if await CheckNotification.requestAuthorization() { s.setReminder(true) }
                }
                dismiss()
            }, onNo: { dismiss() })
        case .basket:
            BasketAsk(potato: store.state.basketAsk(today: store.today))
        }
    }

    private var floor: String { store.state.habit?.floor ?? "" }
}

/// 竹籃裡的一顆，每週問一句。答完 basketAsk 會換人，所以打開那一刻的留著
private struct BasketAsk: View {
    @State private var potato: Potato?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(potato: Potato?) { _potato = State(initialValue: potato) }

    var body: some View {
        AskCard(potato: true, title: "「\(potato?.floor ?? "")」\n現在還會做嗎？", yes: "會", no: "有點掉了",
                onYes: { answer(true) }, onNo: { answer(false) })
    }

    private func answer(_ still: Bool) {
        if let potato { store.answerBasket(potato, still: still) }
        dismiss()
    }
}

/// 一句話、兩顆按鈕
private struct AskCard: View {
    var potato = false
    var title: String
    var yes: String
    var no: String
    var onYes: () -> Void
    var onNo: () -> Void

    var body: some View {
        SheetFrame {
            if potato {
                PotatoView(width: 140) // domy-ignore: 插畫尺寸
                    .frame(maxWidth: .infinity)
                    .padding(.top, Sp.s4)
            }
            Text(title)
                .domyType(Ty.title2)
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Sp.s4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: Sp.s2) {
                DomyButton(yes) { onYes() }
                DomyButton(no, variant: .secondary) { onNo() }
            }
        }
    }
}

// MARK: - 開始四問

/// 四句自動化量表，一題一頁，點了就到下一題。沒有預設分數
struct ReviewQuestions: View {
    @Environment(Store.self) private var store
    var onSubmit: ([Double]) -> Void
    var later: () -> Void
    @State private var scores: [Int] = [0, 0, 0, 0]
    @State private var step = 0
    /// 點了分數、還沒換到下一題
    @State private var moving = false

    var body: some View {
        let questions = Phrases.reviewQuestions(floor: store.state.habit?.floor ?? "")
        SheetFrame {
            HStack(spacing: Sp.s2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.accent : Theme.surfaceMuted)
                        .frame(height: Sp.s1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(step + 1) 題，共 4 題")
            HStack {
                if step > 0 {
                    DomyButton("上一題", variant: .quiet, size: .compact) {
                        guard !moving else { return }
                        withAnimation(Feel.transition) { step -= 1 }
                    }
                }
                Spacer(minLength: 0)
                DomyButton("晚點再說", variant: .quiet, size: .compact) { later() }
            }
            Text(questions[step])
                .domyType(Ty.title2)
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Sp.s4)
                .id(step)
                .transition(.opacity)
            VStack(spacing: Sp.s2) {
                ScalePicker(title: questions[step], selection: picked)
                    .accessibilityIdentifier("review-q\(step + 1)")
                HStack {
                    Text("完全不像")
                    Spacer()
                    Text("完全就是")
                }
                .domyType(Ty.footnote)
                .foregroundStyle(Theme.fg2)
                .accessibilityHidden(true)
            }
        }
    }

    private var picked: Binding<Int> {
        Binding(get: { scores[step] }, set: { v in
            guard !moving else { return }
            scores[step] = v
            moving = true
            Task {
                // 讓選到的那顆看得見再換題
                try? await Task.sleep(for: .seconds(0.3))
                moving = false
                if step < 3 {
                    withAnimation(Feel.transition) { step += 1 }
                } else if scores.allSatisfy({ $0 >= 1 }) {
                    onSubmit(scores.map(Double.init))
                }
            }
        })
    }
}

// MARK: - 試兩週

/// 試兩週到了：攤天數，結論由她下
struct TrialResultCard: View {
    var result: TrialResult
    @Environment(Store.self) private var store

    private var trial: Trial? { store.state.trials.first(where: { $0.id == result.trial.id }) }

    var body: some View {
        VStack(alignment: .leading, spacing: Sp.s3) {
            VStack(alignment: .leading, spacing: Sp.s2) {
                ForEach(Array(store.state.trialText(result).enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .domyType(i == 0 ? Ty.body : Ty.subheadline)
                        .foregroundStyle(i == 0 ? Theme.fg : Theme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if trial?.status == .running {
                Text(Copy.t(.expQ))
                    .domyType(Ty.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.fg)
                let options = [Copy.Option(code: "keep", text: Copy.t(.expKeep)),
                               Copy.Option(code: "no_difference", text: Copy.t(.expSame)),
                               Copy.Option(code: "again", text: Copy.t(.expAgain)),
                               Copy.Option(code: "unanswered", text: Copy.t(.skip))]
                ChipFlow(items: options.map(\.text), accent: false, selected: nil) { text in
                    guard let o = options.first(where: { $0.text == text }) else { return }
                    store.concludeTrial(result.trial.id, o.code)
                }
            } else {
                Text(reply)
                    .domyType(Ty.footnote)
                    .foregroundStyle(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Sp.s5)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Rd.xxl, style: .continuous))
    }

    private var reply: String {
        if trial?.conclusion == "again", let next = store.state.runningTrial {
            return Copy.t(.expAgainOK, ["end": next.end.short])
        }
        return Copy.t(.done)
    }
}
