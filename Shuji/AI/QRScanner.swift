import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// 掃 QR code（連電腦的 Claude 用，搬自蘿蔔旅行）。只認 QR code，掃到第一個就交出去。
/// 模擬器和比較舊的 iPhone 沒有這個功能，isAvailable 是 false，畫面改成貼網址。
/// 相機權限在進到掃描畫面時才問；被拒絕就在這裡給「打開設定」。
struct QRScanner: View {
    var onFound: (String) -> Void
    @Environment(\.openURL) private var openURL
    @State private var gate = Gate.asking

    /// 在等使用者回答、可以掃、相機權限被關、相機被別的原因擋住
    private enum Gate { case asking, ready, denied, blocked }

    /// 這支手機有沒有掃描功能。不看相機權限：還沒問過的要讓人按得進來才問得到
    @MainActor static var isAvailable: Bool { DataScannerViewController.isSupported }

    var body: some View {
        ZStack {
            Theme.canvas
            switch gate {
            case .asking:
                EmptyView()
            case .ready:
                QRCamera(onFound: onFound, onFail: { gate = .blocked })
                    .accessibilityElement()
                    .accessibilityLabel("相機，對準電腦上的 QR code")
            case .denied:
                VStack(spacing: Sp.s2) {
                    DomyEmptyState(icon: "camera", title: "相機沒有打開")
                    DomyButton("打開設定", fullWidth: false) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            case .blocked:
                DomyEmptyState(icon: "camera", title: "相機現在不能用", detail: "關掉這頁，改貼網址。")
            }
        }
        .task { await askCamera() }
    }

    private func askCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            gate = .ready
        case .notDetermined:
            gate = await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        case .restricted:
            gate = .blocked
        default:
            gate = .denied
        }
    }
}

/// 相機畫面本身。相機開不起來就叫 onFail
private struct QRCamera: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    var onFail: () -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced,
                                           recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        // 畫面還沒出來時開相機會失敗，等下一輪再開
        let owner = context.coordinator
        DispatchQueue.main.async {
            do {
                try vc.startScanning()
            } catch {
                owner.fail()
            }
        }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound, onFail: onFail) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        let onFail: () -> Void
        private var done = false

        init(onFound: @escaping (String) -> Void, onFail: @escaping () -> Void) {
            self.onFound = onFound
            self.onFail = onFail
        }

        func fail() {
            guard !done else { return }
            done = true
            onFail()
        }

        /// 掃到一半相機被收走（例如權限被關）
        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            fail()
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue, !text.isEmpty {
                    done = true
                    Haptic.select()
                    onFound(text)
                    return
                }
            }
        }
    }
}
