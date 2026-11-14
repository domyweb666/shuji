import Foundation
import Observation
import StoreKit

/// 完整版：一次買斷，不訂閱（ai/AI交接.md 第二節）。
/// 解鎖週回顧建議、季稽核、小工具。核心動作與其他 AI 功能永遠免費。
/// 商品要先在 App Store Connect 建好：非消耗型，Product ID 跟下面一樣。
@MainActor
@Observable
final class Purchases {
    static let shared = Purchases()
    static let productID = "org.domyweb.shuji.full"

    private(set) var owned = false
    private(set) var product: Product?
    private(set) var busy = false
    var message: String?

    /// 測試區「假裝買了完整版」，只有 Debug 建置有用
    var debugFull: Bool = UserDefaults.standard.bool(forKey: "shuji.debugFull") {
        didSet {
            UserDefaults.standard.set(debugFull, forKey: "shuji.debugFull")
            onChange?(isFull)
        }
    }

    var isFull: Bool {
        #if DEBUG
        return owned || debugFull
        #else
        return owned
        #endif
    }

    /// 完整版狀態變了（買了、退款），小工具要重畫
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { [weak self] in
            await self?.refresh()
            await self?.loadProduct()
        }
    }

    func refresh() async {
        var has = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil {
                has = true
            }
        }
        let changed = has != owned
        owned = has
        if changed { onChange?(isFull) }
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    func buy() async {
        message = nil
        if product == nil { await loadProduct() }
        guard let product else {
            message = "現在連不到 App Store，等一下再試。"
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    await refresh()
                } else {
                    message = "這筆購買驗證不過，沒有解鎖。"
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            message = "沒買成，等一下再試。"
        }
    }

    func restore() async {
        message = nil
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        if !owned { message = "這個 Apple ID 沒有買過完整版。" }
    }
}
