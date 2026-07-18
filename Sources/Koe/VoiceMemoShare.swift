import AppKit

/// 🔥 焚き火(takibi.wtf)への投稿。音声現物は上げず、テキスト(要約+文字起こし冒頭)のみを
/// 既存の atsm_log ツールに乗せる(薪はテキスト文化・録音の生データを外に出さない安全側の判断)。
final class VoiceMemoShare {
    static let shared = VoiceMemoShare()

    private static let endpoint = URL(string: "https://takibi.wtf/mcp")!
    private static let keychainKey = "takibiApiKey"

    enum ShareOutcome {
        case success(logID: String?)
        case failure(String)
    }

    func postToTakibi(_ record: VoiceMemoRecord, completion: @escaping (ShareOutcome) -> Void) {
        guard let apiKey = resolveApiKey() else {
            completion(.failure("キーが未設定です"))
            return
        }
        let body = Self.buildMessage(record)
        Task {
            let outcome = await Self.callAtsmLog(apiKey: apiKey, message: body)
            await MainActor.run { completion(outcome) }
        }
    }

    private static func buildMessage(_ record: VoiceMemoRecord) -> String {
        var lines: [String] = [record.displayTitle]
        if let summary = record.summary, !summary.isEmpty {
            lines.append("要約: \(summary)")
        }
        if let transcript = record.transcript, !transcript.isEmpty {
            lines.append(String(transcript.prefix(200)))
        }
        return lines.joined(separator: "\n")
    }

    private static func callAtsmLog(apiKey: String, message: String) async -> ShareOutcome {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "atsm_log", "arguments": ["message": message]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: req)
        } catch {
            return .failure("接続失敗: \(error.localizedDescription)")
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"] as? [String: Any]
        else {
            return .failure("応答を解釈できませんでした")
        }
        if (result["isError"] as? Bool) == true {
            let content = (result["content"] as? [[String: Any]])?.first?["text"] as? String
            return .failure((content ?? "不明なエラー").prefix(120).description)
        }
        let content = (result["content"] as? [[String: Any]])?.first?["text"] as? String
        return .success(logID: content)
    }

    // MARK: - API キー(Keychain・初回はペースト。VoiceMessageWindow と同じ導線)

    private func resolveApiKey() -> String? {
        if let k = KeychainHelper.get(Self.keychainKey), !k.isEmpty { return k }
        let alert = NSAlert()
        alert.messageText = "焚き火 API キーが未設定です"
        alert.informativeText = "takibi.wtf/connect で発行した api_token を貼り付けてください（Keychain に保存されます）。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "api_token"
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        KeychainHelper.set(key, for: Self.keychainKey)
        return key
    }
}
