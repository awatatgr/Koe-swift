import Foundation

/// 録音停止 → 自動で文字起こしをキックする直列キュー。WhisperContext は shared シングルトンで
/// チャンクごとに内部同期するため並列化せず1件ずつ処理する(FileTranscriber の設計に合わせる)。
final class VoiceMemoTranscriptionQueue {
    static let shared = VoiceMemoTranscriptionQueue()

    private var pending: [UUID] = []
    private var isProcessing = false
    private var currentTranscriber: FileTranscriber?

    func enqueue(_ id: UUID) {
        DispatchQueue.main.async {
            guard !self.pending.contains(id) else { return }
            self.pending.append(id)
            VoiceMemoLibrary.shared.update(id: id) { $0.transcriptStatus = .queued }
            self.processNextIfIdle()
        }
    }

    /// 手動「再文字起こし」用: 既存の transcript を破棄して再キュー
    func retranscribe(_ id: UUID) {
        VoiceMemoLibrary.shared.update(id: id) { rec in
            rec.transcript = nil
            rec.summary = nil
        }
        enqueue(id)
    }

    private func processNextIfIdle() {
        guard !isProcessing, let id = pending.first else { return }
        guard let record = VoiceMemoLibrary.shared.record(id: id) else {
            pending.removeFirst()
            processNextIfIdle()
            return
        }

        // whisper.cpp のモデルロードは AppDelegate 起動時に走るが、稀に間に合わないタイミングがある。
        // 失敗として扱わず 15 秒後にリトライする(ユーザー操作不要で自然に通る)。
        guard WhisperContext.shared.isLoaded else {
            klog("VoiceMemoTranscriptionQueue: whisper not loaded yet, retry in 15s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                self?.processNextIfIdle()
            }
            return
        }

        isProcessing = true
        VoiceMemoLibrary.shared.update(id: id) { $0.transcriptStatus = .running(0) }

        let transcriber = FileTranscriber()
        currentTranscriber = transcriber
        transcriber.transcribe(
            url: record.fileURL,
            progress: { [weak self] completed, total in
                guard self != nil else { return }
                let ratio = total > 0 ? Double(completed) / Double(total) : 0
                VoiceMemoLibrary.shared.update(id: id) { $0.transcriptStatus = .running(ratio) }
            },
            completion: { [weak self] text, error in
                guard let self else { return }
                if let text, !text.isEmpty {
                    VoiceMemoLibrary.shared.updateAndSaveNow(id: id) { rec in
                        rec.transcript = text
                        rec.transcriptStatus = .done
                    }
                    klog("VoiceMemoTranscriptionQueue: done id=\(id) chars=\(text.count)")
                    VoiceMemoSummarizer.shared.summarizeIfNeeded(id: id)
                } else {
                    VoiceMemoLibrary.shared.updateAndSaveNow(id: id) { rec in
                        rec.transcriptStatus = .failed(error ?? "不明なエラー")
                    }
                    klog("VoiceMemoTranscriptionQueue: failed id=\(id) error=\(error ?? "?")")
                }
                self.currentTranscriber = nil
                self.isProcessing = false
                if !self.pending.isEmpty { self.pending.removeFirst() }
                self.processNextIfIdle()
            }
        )
    }
}
