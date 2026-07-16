import AppKit
import WebKit

/// 📻 KOE ラジオ — koe.live/live（24時間・多声・本人声のAIラジオ「声の部屋」）を、
/// ネイティブ Koe.app の中からそのまま聴けるようにする(v3新機能)。
/// デザインは koe.live 側の暖色ブランドに完全に委ね、ネイティブ再実装はしない(KoeWebWindowと同じ方針)。
final class KoeLiveWindow: NSObject, NSWindowDelegate, WKUIDelegate {
    static let shared = KoeLiveWindow()

    private var window: NSWindow?
    private var webView: WKWebView?
    private static let liveURL = URL(string: "https://koe.live/live")!

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []  // 開いた瞬間に流れる=このウィンドウの目的
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 700), configuration: cfg)
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = false
        wv.load(URLRequest(url: Self.liveURL))
        self.webView = wv

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "📻 KOE ラジオ"
        w.minSize = NSSize(width: 360, height: 520)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = wv
        w.center()
        self.window = w
    }

    // ⚠ ウィンドウを閉じても音が流れ続けるのは事故なので、閉じたら確実に停止する。
    func windowWillClose(_ notification: Notification) {
        webView?.evaluateJavaScript("document.querySelectorAll('audio,video').forEach(function(m){m.pause()})", completionHandler: nil)
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
    }
}
