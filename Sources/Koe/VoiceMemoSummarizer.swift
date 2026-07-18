import Foundation

/// 文字起こし完了後に自動で日本語要約(120字以内)を生成する。
/// 生成した要約は M5SpeakClient が誤読ゼロ本人声で読み上げるための素材になる。
final class VoiceMemoSummarizer {
    static let shared = VoiceMemoSummarizer()

    private static let maxSummaryChars = 120
    private static let instruction = """
    以下は録音の文字起こしです。日本語で3文以内・\(maxSummaryChars)字以内に要約してください。
    要約文のみを出力し、前置きや「要約:」などのラベルは付けないでください。
    """

    func summarizeIfNeeded(id: UUID) {
        guard let record = VoiceMemoLibrary.shared.record(id: id), let transcript = record.transcript,
              !transcript.isEmpty else { return }

        // 文字起こしが既に短ければ LLM を呼ばず全文をそのまま要約として使う(コスト削減・レイテンシ削減)。
        if transcript.count <= Self.maxSummaryChars {
            VoiceMemoLibrary.shared.updateAndSaveNow(id: id) { $0.summary = transcript }
            return
        }

        LLMProcessor.shared.process(text: transcript, instruction: Self.instruction) { result in
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard VoiceMemoLibrary.shared.record(id: id) != nil else { return }
                // LLM 失敗時(空文字)は要約なしに倒し、UI側は文字起こし冒頭を読み上げる(自動降格方針)。
                let summary = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxSummaryChars))
                VoiceMemoLibrary.shared.updateAndSaveNow(id: id) { $0.summary = summary }
                klog("VoiceMemoSummarizer: id=\(id) summary=\(summary?.count ?? 0)chars")
            }
        }
    }
}
