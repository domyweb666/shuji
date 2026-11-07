import AVFoundation

/// 原型用 WebAudio 現場合成兩個音：thunk（按到了）、ping（開花）。
/// 這裡照同樣的參數先算成 PCM 緩衝，用 AVAudioEngine 播。
/// 用 ambient 類別：靜音鍵切掉就不出聲，也不會打斷正在播的音樂。
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    private var thunkBuffer: AVAudioPCMBuffer?
    private var pingBuffer: AVAudioPCMBuffer?

    private struct Pluck {
        var freq: Double
        var dur: Double
        var triangle: Bool
        var vol: Double
        var delay: Double = 0
    }

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// 按下去那一刻先把引擎叫醒，按滿時播放就不會慢半拍
    func prime() { _ = start() }

    func thunk() {
        if thunkBuffer == nil {
            thunkBuffer = render([
                Pluck(freq: 150, dur: 0.22, triangle: true, vol: 0.5),
                Pluck(freq: 300, dur: 0.12, triangle: false, vol: 0.18),
            ])
        }
        play(thunkBuffer)
    }

    func ping() {
        if pingBuffer == nil {
            pingBuffer = render([
                Pluck(freq: 880, dur: 0.5, triangle: false, vol: 0.16),
                Pluck(freq: 1320, dur: 0.4, triangle: false, vol: 0.08, delay: 0.07),
            ])
        }
        play(pingBuffer)
    }

    private func start() -> Bool {
        if engine.isRunning { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer, start() else { return }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func render(_ plucks: [Pluck]) -> AVAudioPCMBuffer? {
        let total = (plucks.map { $0.delay + $0.dur }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(total * sampleRate)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = frames
        let count = Int(frames)
        for i in 0..<count { data[i] = 0 }

        for p in plucks {
            var phase = 0.0
            var lowpass = 0.0
            let alpha = 1 - exp(-2 * Double.pi * (p.freq * 6) / sampleRate)
            let startFrame = Int(p.delay * sampleRate)
            let n = Int(p.dur * sampleRate)
            for j in 0..<n {
                let tt = Double(j) / sampleRate
                // 頻率從 1.6 倍指數滑到目標，30 毫秒內
                let f = tt < 0.03 ? p.freq * pow(1.6, 1 - tt / 0.03) : p.freq
                phase += 2 * Double.pi * f / sampleRate
                let s = sin(phase)
                let wave = p.triangle ? (2 / Double.pi) * asin(s) : s
                // 音量 5 毫秒內拉到 vol，再指數衰減到 0.0001
                let env: Double
                if tt < 0.005 {
                    env = p.vol * tt / 0.005
                } else {
                    env = p.vol * pow(0.0001 / p.vol, (tt - 0.005) / max(0.001, p.dur - 0.005))
                }
                lowpass += alpha * (wave * env - lowpass)
                let idx = startFrame + j
                if idx < count { data[idx] += Float(lowpass) }
            }
        }
        for i in 0..<count { data[i] = max(-1, min(1, data[i])) }
        return buf
    }
}
