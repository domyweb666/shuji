import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 底部彈出卡共用的外框
private struct SheetFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: 560)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }
}

private struct SheetTitle: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.title2.weight(.bold)).padding(.horizontal, 2) }
}

private struct SheetNote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.fg2).lineSpacing(4).padding(.horizontal, 2)
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
                    RowButton(text: "撤銷今天", chevron: false, color: Theme.danger) {
                        store.undoToday()
                        dismiss()
                    }
                }
            }
            if leaving {
                Card {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("請假的原因，一行就好").font(.footnote).foregroundStyle(Theme.fg2)
                        TextField("出遠門、發燒…", text: $reason)
                            .focused($reasonFocused)
                            .submitLabel(.done)
                            .onChange(of: reason) { _, v in if v.count > 40 { reason = String(v.prefix(40)) } }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.rowInset)
                    .padding(.vertical, 12)
                }
                if let lastReason { SheetNote("上次請假：\(lastReason)") }
                if sameReason { SheetNote("這個原因第二次了，可能是開關要換。") }
                PrimaryButton(title: "請假") {
                    store.leaveToday(reason: reason)
                    dismiss()
                }
                .padding(.top, 4)
            }
            SheetNote("補記只能補昨天，而且是補紀錄，不是補做。")
        }
    }
}

// MARK: 開始四問

struct ReviewSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var scores: [Double] = [4, 4, 4, 4]

    var body: some View {
        SheetFrame {
            SheetTitle("開始四問")
            SheetNote("只問開始那一下，不問做得好不好。1 是完全不像，7 是完全就是。")
            let questions = Phrases.reviewQuestions(floor: store.state.habit?.floor ?? "")
            ForEach(0..<4, id: \.self) { i in
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(questions[i]).font(.system(size: 16)).lineSpacing(4)
                        Picker(questions[i], selection: $scores[i]) {
                            ForEach(1...7, id: \.self) { n in
                                Text("\(n)").tag(Double(n))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
                }
            }
            PrimaryButton(title: "記下這週") {
                store.recordReview(scores: scores)
                dismiss()
            }
        }
    }
}

// MARK: 讓開始更容易（從設定頁搬過來，卡住的時候才看）

struct TipsSheet: View {
    var body: some View {
        SheetFrame {
            SheetTitle("讓開始更容易")
            SheetNote("開關出現的那一刻，手邊的阻力越小越好。三件前一晚就能做的事：")
            Card {
                ForEach(Array(Phrases.tips.enumerated()), id: \.offset) { i, tip in
                    if i > 0 { RowSep() }
                    RowLabel(text: tip)
                }
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
        HStack(spacing: 12) {
            Text(name)
            Spacer()
            Text(number).foregroundStyle(Theme.fg2).monospacedDigit().textSelection(.enabled)
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 12)
        .frame(minHeight: Theme.rowHeight)
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
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.accent, in: Capsule())
                }
            }
            PrimaryButton(title: "複製成文字", ghost: true) {
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

    var body: some View {
        SheetFrame {
            SheetTitle("從備份還原")
            SheetNote("貼上之前匯出的那段文字，或選一個備份檔。目前的資料會被取代。")
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .autocorrectionDisabled()
            PrimaryButton(title: "選備份檔", ghost: true) { picking = true }
            if failed {
                Text("這段讀不出來，確認是完整複製的那一整段。")
                    .font(.subheadline).foregroundStyle(Theme.danger).padding(.horizontal, 2)
            }
            PrimaryButton(title: "還原") {
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
            HStack { Spacer(); PotatoView(width: 120); Spacer() }
            Text(potato.floor)
                .font(.title2.weight(.bold))
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
