import SwiftUI

/// Koe Lux ブランドの波形トーン(ゴールド→アンバー)。VoiceRecorderView.swift の RecLux と値を揃える。
private let waveformGradient = LinearGradient(
    colors: [Color(red: 0.85, green: 0.55, blue: 0.40).opacity(0.95),
             Color(red: 0.78, green: 0.68, blue: 0.50).opacity(0.55)],
    startPoint: .bottom, endPoint: .top
)
private let waveformPlayedColor = Color(red: 0.78, green: 0.68, blue: 0.50)

/// リアルタイム録音中の波形。iOS版 Koe-iOS/Sources/WaveformView.swift と同じ
/// 「レベル値をシフトバッファに積んでスクロールさせる」方式の移植(mac側は棒数を増やし横幅いっぱいに)。
struct RecorderWaveformView: View {
    let level: Float
    @State private var bars: [Float] = Array(repeating: 0.05, count: 60)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bars.count, id: \.self) { i in
                Capsule()
                    .fill(waveformGradient)
                    .frame(minWidth: 2)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: CGFloat(bars[i]), anchor: .center)
                    .animation(.easeOut(duration: 0.08), value: bars[i])
            }
        }
        .onChange(of: level) { newLevel in
            var newBars = bars
            for i in 0..<newBars.count - 1 { newBars[i] = newBars[i + 1] }
            newBars[newBars.count - 1] = max(0.05, min(1.0, newLevel))
            bars = newBars
        }
    }
}

/// 停止後の静的波形(peaks配列をCanvasで棒描画)。クリックでシークできる。
struct StaticWaveformView: View {
    let peaks: [Float]
    /// 0.0-1.0 の再生位置(nilなら未再生)
    var progress: Double?
    var onSeek: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !peaks.isEmpty else { return }
                let barWidth = size.width / CGFloat(peaks.count)
                let progressX = progress.map { CGFloat($0) * size.width }
                for (i, p) in peaks.enumerated() {
                    let x = CGFloat(i) * barWidth
                    let h = max(1.5, CGFloat(p) * size.height)
                    let y = (size.height - h) / 2
                    let played = progressX.map { x < $0 } ?? false
                    let color: Color = played ? waveformPlayedColor : Color.secondary.opacity(0.35)
                    let rect = CGRect(x: x, y: y, width: max(1, barWidth - 1), height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard geo.size.width > 0 else { return }
                        let ratio = max(0, min(1, value.location.x / geo.size.width))
                        onSeek?(Double(ratio))
                    }
            )
        }
    }
}
