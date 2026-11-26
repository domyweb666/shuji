import AVFoundation
import UIKit

/// 原型用 WebAudio 現場合成兩個音：thunk（按到了）、ping（開花）。
/// 這裡照同樣的參數先算成 PCM 緩衝，用 AVAudioEngine 播。
/// 用 ambient 類別：靜音鍵切掉就不出聲，也不會打斷正在播的音樂。
///
/// 引擎、session、緩衝全部只在 `queue` 這條序列佇列上碰，主執行緒只負責丟工作過去，
/// 所以第一次開機（setCategory、setActive、engine.start）不會卡住按下去那一格（效能審查 2026-11-26 第 1 列）。
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// 最後一次播完多久把引擎暫停，省電
    private static let idleDelay: TimeInterval = 3

    private let queue = DispatchQueue(label: "shuji.sound", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    // 以下都只在 queue 上讀寫
    private var wired = false
    private var sessionReady = false
    private var thunkBuffer: AVAudioPCMBuffer?
    private var pingBuffer: AVAudioPCMBuffer?
    private var idle: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

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
        // 接線和算兩個音都丟到背景，init 本身不做重活
        queue.async { [weak self] in
            self?.wire()
            self?.renderBuffers()
        }

        let center = NotificationCenter.default
        // 進背景就停，不要掛著音訊硬體
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.halt() }
        })
        // 被電話、鬧鐘打斷：系統會把引擎停掉、session 也可能被關，下次播時重新開
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.sessionReady = false }
        })
    }

    /// 「今天」頁出現時先叫：在背景把 session 和引擎開起來，按下去就不用等
    func warmUp() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.start() { self.scheduleIdle() }
        }
    }

    /// 按下去那一刻先把引擎叫醒，按滿時播放就不會慢半拍
    func prime() { warmUp() }

    func thunk() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.thunkBuffer == nil { self.renderBuffers() }
            self.play(self.thunkBuffer)
        }
    }

    func ping() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.pingBuffer == nil { self.renderBuffers() }
            self.play(self.pingBuffer)
        }
    }

    // MARK: 以下只在 queue 上跑

    private func wire() {
        guard !wired else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        wired = true
    }

    private func renderBuffers() {
        if thunkBuffer == nil {
            thunkBuffer = render([
                Pluck(freq: 150, dur: 0.22, triangle: true, vol: 0.5),
                Pluck(freq: 300, dur: 0.12, triangle: false, vol: 0.18),
            ])
        }
        if pingBuffer == nil {
            pingBuffer = render([
                Pluck(freq: 880, dur: 0.5, triangle: false, vol: 0.16),
                Pluck(freq: 1320, dur: 0.4, triangle: false, vol: 0.08, delay: 0.07),
            ])
        }
    }

    private func start() -> Bool {
        wire()
        if engine.isRunning { return true }
        do {
            if !sessionReady {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, options: [.mixWithOthers])
                try session.setActive(true)
                sessionReady = true
            }
            try engine.start()
            return true
        } catch {
            sessionReady = false
            return false
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer, start() else { return }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        scheduleIdle()
    }

    /// 最後一次叫醒或播放之後 3 秒沒事就暫停引擎；再播時 start() 會自己接上
    private func scheduleIdle() {
        idle?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.engine.isRunning else { return }
            self.engine.pause()
        }
        idle = item
        queue.asyncAfter(deadline: .now() + SoundPlayer.idleDelay, execute: item)
    }

    /// 進背景：整個停掉，回來第一次播再開
    private func halt() {
        idle?.cancel()
        idle = nil
        guard wired else { return }
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
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
