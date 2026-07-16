import AVFoundation
import Foundation

/// 「ヘイ、Koe」ウェイクワードで起動した発話を koe.live/agent と同じ頭脳(Claude+MCP)に送る。
/// 契約は koe-edge の AGENT_PAGE(/agent) の client JS と同一:
///   POST /api/agent {text,voice,name} → {reply, speak?, req_id?, links?}
///   speak.text があれば POST /api/speak → mp3 を再生
///   req_id があれば依頼として記録済み。GET /api/agent/result?id= を6秒毎にポーリングして結果を待つ
/// (2026-07-14 本人指示「ヘイ、Koeで、パーソナリティじゃなくてエージェントを起動したい」)
final class KoeAgentBridge: NSObject, AVAudioPlayerDelegate {
    static let shared = KoeAgentBridge()
    private let base = "https://koe.live"
    private var player: AVAudioPlayer?
    private var livePlayer: AVAudioPlayer?
    private var liveActive = false

    /// 音声認識テキストをエージェントへ送る。即時応答(hint/speak/radio/profile)はここでcompletionを1回呼ぶ。
    /// 依頼(req_id)の場合は先に受理メッセージでcompletionを呼び、結果が出たらもう一度completionを呼ぶ。
    func send(_ text: String, voiceID: String, completion: @escaping (String) -> Void) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { completion("聞き取れませんでした"); return }
        guard let url = URL(string: base + "/api/agent") else { completion("Koeエージェントに接続できませんでした"); return }
        stopLive()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": t, "voice": voiceID, "name": "Koe Mac"])

        klog("KoeAgent: send '\(t.prefix(80))'")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self, let data, error == nil,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                klog("KoeAgent: request failed: \(error?.localizedDescription ?? "bad response")")
                DispatchQueue.main.async { completion("Koeエージェントに接続できませんでした") }
                return
            }
            let reply = (j["reply"] as? String) ?? "受け取りました"
            klog("KoeAgent: reply '\(reply.prefix(80))'")
            DispatchQueue.main.async { completion(reply) }

            if let speak = j["speak"] as? [String: Any], let speakText = speak["text"] as? String, !speakText.isEmpty {
                self.speak(speakText, voiceID: (speak["voice"] as? String) ?? voiceID)
            }
            if let reqID = j["req_id"] as? String, !reqID.isEmpty {
                self.pollResult(reqID: reqID, completion: completion)
            }
            if (j["kind"] as? String) == "listen" {
                self.playLive()
            }
        }.resume()
    }

    /// 📻 Koe Live(ラジオ/番組)を再生する。/lounge のrNext相当を端末側で継続再生(2026-07-14本人指示「liveも聞けるようにして」)。
    func playLive(idx: Int? = nil) {
        liveActive = true
        var comps = URLComponents(string: base + "/api/live/now")
        comps?.queryItems = [URLQueryItem(name: "lang", value: "ja")] + (idx.map { [URLQueryItem(name: "i", value: String($0))] } ?? [])
        guard let url = comps?.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self, self.liveActive, let data, error == nil,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mode = j["mode"] as? String, mode == "ai" || mode == "live",
                  let trackURLStr = j["url"] as? String, let trackURL = URL(string: trackURLStr) else { return }
            let nextIdx = (j["idx"] as? Int).map { $0 + 1 }
            klog("KoeAgent(live): playing '\((j["title"] as? String ?? "").prefix(40))'")
            URLSession.shared.dataTask(with: trackURL) { audioData, _, audioErr in
                guard self.liveActive, let audioData, audioErr == nil else { return }
                DispatchQueue.main.async {
                    do {
                        self.livePlayer = try AVAudioPlayer(data: audioData)
                        self.livePlayer?.delegate = self
                        self.livePlayer?.play()
                        self.pendingLiveNextIdx = nextIdx
                    } catch {
                        klog("KoeAgent(live): play error: \(error)")
                    }
                }
            }.resume()
        }.resume()
    }

    func stopLive() {
        liveActive = false
        livePlayer?.stop()
        livePlayer = nil
    }

    private var pendingLiveNextIdx: Int?

    private func speak(_ text: String, voiceID: String) {
        stopLive()
        guard let url = URL(string: base + "/api/speak") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text, "user_id": voiceID.isEmpty ? "yuki" : voiceID, "source": "agent",
        ])
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            guard let self, let data, error == nil,
                  (resp as? HTTPURLResponse)?.statusCode == 200 else {
                klog("KoeAgent: speak failed: \(error?.localizedDescription ?? "bad status")")
                return
            }
            DispatchQueue.main.async {
                do {
                    self.player = try AVAudioPlayer(data: data)
                    self.player?.delegate = self
                    self.player?.play()
                } catch {
                    klog("KoeAgent: audio play error: \(error)")
                }
            }
        }.resume()
    }

    /// 6秒毎に最大50回(=5分)まで /api/agent/result をポーリングし、できたらcompletionへ結果を渡す。
    private func pollResult(reqID: String, attempt: Int = 0, completion: @escaping (String) -> Void) {
        guard attempt < 50 else {
            DispatchQueue.main.async { completion("⏳ まだ作業中みたいです。結果は受信箱/LINEにも届きます") }
            return
        }
        guard let url = URL(string: base + "/api/agent/result?id=" + reqID) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data,
                   let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   j["ok"] as? Bool == true {
                    let result = (j["result"] as? String) ?? "できました"
                    klog("KoeAgent: result '\(result.prefix(80))'")
                    DispatchQueue.main.async { completion("✅ " + result) }
                } else {
                    self.pollResult(reqID: reqID, attempt: attempt + 1, completion: completion)
                }
            }.resume()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player { self.player = nil }
        if self.livePlayer === player {
            self.livePlayer = nil
            if liveActive { playLive(idx: pendingLiveNextIdx) }
        }
    }
}
