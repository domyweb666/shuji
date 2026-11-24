import SwiftUI
import XCTest
import VeggieKit
@testable import Shuji

// 暫時：量彈出頁是不是整頁、內容有沒有超出。量完刪掉。
@MainActor
final class ZZQCTests: XCTestCase {
    struct Host<V: View>: View {
        @State var on = true
        var view: V
        var body: some View { Color.clear.sheet(isPresented: $on) { view } }
    }

    func scrolls(_ v: UIView) -> [UIScrollView] {
        (v is UIScrollView ? [v as! UIScrollView] : []) + v.subviews.flatMap { scrolls($0) }
    }

    func show<V: View>(_ name: String, _ root: V) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert
        w.rootViewController = UIHostingController(rootView: root.tint(Theme.accent).veggieStyle(.shuji))
        w.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(3))
        let top = w.rootViewController?.presentedViewController?.view ?? w.rootViewController!.view!
        print("QCM", name, "window", w.bounds.size, "safe", w.safeAreaInsets, "sheet", top.convert(top.bounds, to: w))
        for s in scrolls(top) {
            print("QCM", name, "scroll frame", s.convert(s.bounds, to: w), "content", s.contentSize, "inset", s.adjustedContentInset)
        }
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        let img = UIGraphicsImageRenderer(size: w.bounds.size, format: f).image { _ in w.drawHierarchy(in: w.bounds, afterScreenUpdates: true) }
        let b64 = img.jpegData(compressionQuality: 0.5)!.base64EncodedString()
        var i = b64.startIndex
        var n = 0
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 6000, limitedBy: b64.endIndex) ?? b64.endIndex
            print("QCI|\(name)|\(n)|\(b64[i..<j])|")
            n += 1
            i = j
        }
        w.isHidden = true
    }

    func testSheets() async throws {
        try await show("paywall", Host(view: PaywallSheet()))
        try await show("unfit", Host(view: UnfitSheet()))
        try await show("family", NavigationStack { VeggieFamilyView(config: .shuji) })
    }
}
