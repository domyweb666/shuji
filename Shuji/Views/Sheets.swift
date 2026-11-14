import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 底部彈出卡共用的外框：畫布色、左右 20、區塊之間 16
struct SheetFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Sp.s4) { content }
                .padding(.horizontal, Sz.screenMargin)
                .padding(.top, Sp.s6)
                .padding(.bottom, Sp.s8)
                .frame(maxWidth: Theme.contentMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Rd.xxl)
        .presentationBackground(Theme.canvas)
        .tint(Theme.accent)
    }
}

struct SheetTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .domyType(Ty.title2)
            .foregroundStyle(Theme.fg)
            .padding(.horizontal, Sp.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SheetNote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .domyType(Ty.subheadline)
            .foregroundStyle(Theme.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Sp.s1)
    }
}

// MARK: 今天的更多選項

struct MoreSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var leaving = false
    @State private var reason = ""
    @FocusState private var reasonFocused: Bool

    private var t: DayKey { store.today }
    private var log: DayLog? { store.state.log(on: t) }
    private var leaveLeft: Int { store.state.stats(today: t).leaveLeft }
    private var lastReason: String? { store.lastLeaveReason }
    private var sameReason: Bool {
        guard let lastReason else { return false }
        let v = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return !v.isEmpty && v == lastReason
    }

    var body: some View {
        SheetFrame {
            SheetTitle("今天")
            Card {
                if store.canBackfillYesterday {
                    RowButton(text: "昨天做了，忘了記") {
                        store.backfillYesterday()
                        dismiss()
                    }
                }
                if log == nil {
                    if store.canBackfillYesterday { RowSep() }
                    RowButton(text: "今天請假", value: "本月剩 \(leaveLeft) 次", chevron: false, disabled: leaveLeft == 0) {
                        leaving = true
                        reasonFocused = true
                    }
                }
                if log != nil {
                    RowButton(text: "撤銷今天", chevron: false, tone: .danger) {
                        store.undoToday()
                        dismiss()
                    }
                }
            }
            if leaving {
                VStack(alignment: .leading, spacing: Sp.s2) {
                    Text("請假的原因，一行就好")
                        .domyType(Ty.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.fg)
                        .padding(.horizontal, Sp.s1)
                    TextField("出遠門、發燒…", text: $reason)
                        .focused($reasonFocused)
                        .submitLabel(.done)
                        .onChange(of: reason) { _, v in if v.count > 40 { reason = String(v.prefix(40)) } }
                        .domyField(focused: reasonFocused)
                    if let lastReason { Foot("上次請假：\(lastReason)") }
                }
                if sameReason { WarnBox { Text("這個原因第二次了，可能是開關要換。") } }
                DomyButton("請假") {
                    store.leaveToday(reason: reason)
                    dismiss()
                }
            }
            SheetNote("補記只能補昨天，而且是補紀錄，不是補做。")
        }
    }
}

// MARK: 開始四問

struct ReviewSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 0 代表還沒點。原型預設 4，很多人直接送出，曲線永遠走平，所以改成一定要點
    @State private var scores: [Int] = [0, 0, 0, 0]
    private var allPicked: Bool { scores.allSatisfy { $0 >= 1 } }

    var body: some View {
        SheetFrame {
            SheetTitle("開始四問")
            SheetNote("只問開始那一下，不問做得好不好。1 是完全不像，7 是完全就是。")
            let questions = Phrases.reviewQuestions(floor: store.state.habit?.floor ?? "")
            ForEach(0..<4, id: \.self) { i in
                Card {
                    CardBody(spacing: Sp.s3) {
                        Text("\(i + 1)／4")
                            .domyType(Ty.caption)
                            .foregroundStyle(Theme.strong)
                        Text(questions[i])
                            .domyType(Ty.body)
                            .foregroundStyle(Theme.fg)
                            .fixedSize(horizontal: false, vertical: true)
                        ScalePicker(title: questions[i], selection: $scores[i])
                            .accessibilityIdentifier("review-q\(i + 1)")
                        HStack {
                            Text("完全不像")
                            Spacer()
                            Text("完全就是")
                        }
                        .domyType(Ty.caption)
                        .foregroundStyle(Theme.fg2)
                        .accessibilityHidden(true)
                    }
                }
            }
            DomyButton(allPicked ? "記下這週" : "四題都點一下才能記", disabled: !allPicked) {
                guard allPicked else { return }
                store.recordReview(scores: scores.map(Double.init))
                dismiss()
            }
        }
    }
}

// MARK: 讓開始更容易（從設定頁搬過來，卡住的時候才看）

struct TipsSheet: View {
    @Environment(Store.self) private var store

    var body: some View {
        SheetFrame {
            SheetTitle("讓開始更容易")
            SheetNote("開關出現的那一刻，手邊的阻力越小越好。三件前一晚就能做的事：")
            Card {
                ForEach(Array(Phrases.tips.enumerated()), id: \.offset) { i, tip in
                    if i > 0 { RowSep() }
                    HStack(alignment: .top, spacing: Sp.s3) {
                        Text("\(i + 1)")
                            .domyType(Ty.callout)
                            .foregroundStyle(Theme.strong)
                            .frame(width: Sp.s6, height: Sp.s6)
                            .background(Theme.soft, in: Circle())
                        Text(tip)
                            .domyType(Ty.body)
                            .foregroundStyle(Theme.fg)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Sp.s4)
                    .padding(.vertical, Sp.s3)
                }
            }
            if store.state.habit != nil && AIClient.shared.isAvailable {
                RivalHelper().padding(.top, Sp.s2)
            }
        }
    }
}

// MARK: 什麼時候不適合用這個 app

struct UnfitSheet: View {
    var body: some View {
        SheetFrame {
            SheetTitle("什麼時候不適合用這個 app")
            SheetNote("這個 app 幫你把一個新行為接到生活裡的固定瞬間。下面這些情況，單靠習慣設計不夠，先找專業的人看：")
            Card {
                RowLabel(text: "停不下來的渴望、量控制不了、不做會很難受（菸、酒、賭博、某些網路使用）")
                RowSep()
                RowLabel(text: "做某件事是為了壓下一個停不下來的念頭")
                RowSep()
                RowLabel(text: "拔頭髮、摳皮膚、咬指甲到受傷")
                RowSep()
                RowLabel(text: "跟飲食、體重、身形有關的目標")
                RowSep()
                RowLabel(text: "兩週以上對大部分事情都提不起勁")
            }
            Card {
                hotline("安心專線（24 小時、免付費）", number: "1925")
                RowSep()
                hotline("戒菸專線（免付費）", number: "0800-63-63-63")
            }
            SheetNote("也可以掛精神科、身心科，或找臨床心理師。")
        }
    }

    private func hotline(_ name: String, number: String) -> some View {
        HStack(spacing: Sp.s3) {
            Text(name).domyType(Ty.body).foregroundStyle(Theme.fg)
            Spacer()
            Text(number)
                .domyType(Ty.headline)
                .foregroundStyle(Theme.strong)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .padding(.horizontal, Sp.s4)
        .padding(.vertical, Sp.s3)
        .frame(minHeight: Sz.row)
    }
}

// MARK: 匯出備份

struct ExportSheet: View {
    @Environment(Store.self) private var store
    @State private var fileURL: URL? = nil
    @State private var json = ""

    var body: some View {
        SheetFrame {
            SheetTitle("匯出備份")
            SheetNote("存成一個檔案，放到 iCloud 雲碟、傳給自己都可以。要還原時用「從備份還原」選這個檔，或把內容貼進去。")
            if let fileURL {
                ShareLink(item: fileURL, preview: SharePreview("薯記備份", image: Image(systemName: "leaf"))) {
                    Text("分享備份檔")
                        .domyType(Ty.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: Sz.button)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(DomyPressStyle())
            }
            DomyButton("複製成文字", variant: .secondary) {
                UIPasteboard.general.string = json
                store.show("複製好了。")
            }
            SheetNote("這段文字跟網頁原型的備份是同一種格式，兩邊可以互相還原。")
        }
        .onAppear { prepare() }
    }

    private func prepare() {
        json = store.exportJSON()
        let name = "薯記備份-\(store.today.string).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let data = json.data(using: .utf8), (try? data.write(to: url, options: .atomic)) != nil {
            fileURL = url
        }
    }
}

// MARK: 從備份還原

struct RestoreSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failed = false
    @State private var picking = false
    @FocusState private var editing: Bool

    var body: some View {
        SheetFrame {
            SheetTitle("從備份還原")
            SheetNote("貼上之前匯出的那段文字，或選一個備份檔。目前的資料會被取代。")
            TextEditor(text: $text)
                .font(.system(Ty.footnote.textStyle, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($editing)
                .frame(minHeight: 120) // domy-ignore: 貼上整段 JSON 的高度
                .autocorrectionDisabled()
                .domyField(focused: editing, error: failed)
            if failed {
                HStack(alignment: .top, spacing: Sp.s2) {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    Text("這段讀不出來，確認是完整複製的那一整段。")
                }
                .domyType(Ty.footnote)
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, Sp.s1)
            }
            DomyButton("選備份檔", variant: .secondary) { picking = true }
            DomyButton("還原") {
                if store.importJSON(text) {
                    dismiss()
                } else {
                    failed = true
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.json, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                text = String(decoding: data, as: UTF8.self)
                failed = false
            }
        }
    }
}

// MARK: 竹籃裡的一顆地瓜

struct PotatoSheet: View {
    var potato: Potato

    var body: some View {
        SheetFrame {
            HStack { Spacer(); PotatoView(width: 120); Spacer() } // domy-ignore: 插畫尺寸
                .padding(.vertical, Sp.s2)
                .background(Theme.tint, in: RoundedRectangle(cornerRadius: Rd.xl, style: .continuous))
            Text(potato.floor)
                .domyType(Ty.title2)
                .foregroundStyle(Theme.fg)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Card {
                RowLabel(text: "開關", value: potato.trigger)
                RowSep()
                RowLabel(text: "根", value: "\(potato.nodes) 條")
                RowSep()
                RowLabel(text: "回來", value: "\(potato.ret) 次")
                RowSep()
                RowLabel(text: "種了", value: "\(potato.planted.short) – \(potato.dug.short)")
            }
        }
    }
}
