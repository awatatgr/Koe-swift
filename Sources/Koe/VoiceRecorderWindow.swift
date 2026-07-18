import AppKit
import SwiftUI

/// 🎙 ボイスレコーダー — Apple 標準「ボイスメモ」の完全な置き換えを狙う新機能。
/// 高音質録音+波形+ファイル管理+文字起こし+本人声要約読み上げ+焚き火連携を1ウィンドウに集約する。
/// シングルトン+lazy build は KoeLiveWindow/MeetingChatWindow と同じパターン。
final class VoiceRecorderWindow: NSObject, NSWindowDelegate {
    static let shared = VoiceRecorderWindow()

    private var window: NSWindow?
    private let model = VoiceRecorderViewModel()

    func show() {
        if window == nil { build() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// ⌥⌘R グローバルホットキー用: どこからでも一発でウィンドウを開き、録音をトグルする。
    func toggleViaHotkey() {
        show()
        model.toggleRecording()
    }

    private func build() {
        let rect = NSRect(x: 0, y: 0, width: 760, height: 560)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "🎙 Koe レコーダー"
        win.minSize = NSSize(width: 600, height: 440)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.contentView = NSHostingView(rootView: VoiceRecorderView(model: model))
        win.center()
        self.window = win
    }

    // 録音中にウィンドウを閉じても録音は継続させない(バックグラウンド録音の事故防止)。
    // VoiceMemos.app も同様の挙動。
    func windowWillClose(_ notification: Notification) {
        model.stopIfRecording()
    }
}
