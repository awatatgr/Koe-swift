import SwiftUI
import WebKit

/// koe.live/app（統合Webアプリ＝メッセンジャー/受信箱/焚き火/設定BYOK/通話）をアプリ内に埋め込む。
/// 録音(getUserMedia)はマイク権限を grant して動かす。ネイティブのディクテーション/Whisper等は別タブで温存。
struct WebAppView: UIViewRepresentable {
    let url: URL
    /// ページの読み込みが一段落した時に呼ばれる(2026-07-25 ConnectView用に追加)。
    /// 例: localStorageの中身を覗いて「この人は/boxを持っているか」だけを判定する等、軽い用途向け。
    var onNavigationFinished: ((WKWebView) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onNavigationFinished: onNavigationFinished) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.uiDelegate = context.coordinator
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let onNavigationFinished: ((WKWebView) -> Void)?
        init(onNavigationFinished: ((WKWebView) -> Void)?) {
            self.onNavigationFinished = onNavigationFinished
        }

        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigationFinished?(webView)
        }
    }
}

struct WebAppScreen: View {
    private let appURL = URL(string: "https://koe.live/app")!
    var body: some View {
        WebAppView(url: appURL)
            .ignoresSafeArea(edges: .bottom)
    }
}
