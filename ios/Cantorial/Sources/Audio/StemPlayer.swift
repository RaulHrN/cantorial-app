import AVFoundation
import CantorialCore

/// Plays the user's song and can separate the voice from the instrumental on the fly.
///
/// Lead vocals are normally mixed to the centre of the stereo image, so:
/// - "Sem voz" keeps the side signal (L-R) plus the low end of the centre, which removes the
///   centred voice but keeps bass and kick (the karaoke trick, stereo files only);
/// - "Voz em destaque" lifts the vocal band of the centre and lowers everything else.
///
/// The file is read and processed in small chunks, so memory stays flat and a change of mode
/// is heard within a fraction of a second. Mirrors StemPlayer of the Android app.
final class StemPlayer {
    enum Mix: CaseIterable {
        case original, instrumental, voice

        var label: String {
            switch self {
            case .original: return "Original"
            case .instrumental: return "Sem voz"
            case .voice: return "Voz em destaque"
            }
        }
    }

    /// Read by the scheduling queue; a plain value is enough.
    var mix: Mix = .original
    private(set) var ready = false
    private(set) var failed = false
    /// Voice removal needs two different channels.
    private(set) var stereo = true
    private(set) var durationMs = 0

    private let url: URL
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let queue = DispatchQueue(label: "cantorial.player", qos: .userInitiated)
    private var file: AVAudioFile?
    private var outFormat: AVAudioFormat?
    private var generation = 0
    private var playing = false
    private var fromMs: Float = 0
    private var speed: Float = 1
    private var lastPosition: Float = 0
    private var bass = Biquad.lowPass(sampleRate: 44100, cutoff: 150)
    private var vocalHigh = Biquad.highPass(sampleRate: 44100, cutoff: 180)
    private var vocalLow = Biquad.lowPass(sampleRate: 44100, cutoff: 4500)
    private var configObserver: NSObjectProtocol?
    private static let chunk: AVAudioFrameCount = 8192

    init(url: URL) {
        self.url = url
    }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        player.stop()
        engine.stop()
    }

    func prepare(_ onReady: @escaping () -> Void) {
        if ready || failed { return }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let f = try AVAudioFile(forReading: self.url)
                let rate = f.processingFormat.sampleRate
                guard rate > 0, let out = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { throw CocoaError(.fileReadCorruptFile) }
                self.file = f
                self.outFormat = out
                self.durationMs = Int(Double(f.length) / rate * 1000)
                self.stereo = f.fileFormat.channelCount >= 2
                let r = Float(rate)
                self.bass = Biquad.lowPass(sampleRate: r, cutoff: 150)
                self.vocalHigh = Biquad.highPass(sampleRate: r, cutoff: 180)
                self.vocalLow = Biquad.lowPass(sampleRate: r, cutoff: 4500)
                DispatchQueue.main.async {
                    self.engine.attach(self.player)
                    self.engine.attach(self.timePitch)
                    self.engine.connect(self.player, to: self.timePitch, format: out)
                    self.engine.connect(self.timePitch, to: self.engine.mainMixerNode, format: out)
                    self.engine.prepare()
                    self.configObserver = NotificationCenter.default.addObserver(
                        forName: .AVAudioEngineConfigurationChange, object: self.engine, queue: .main
                    ) { [weak self] _ in
                        // The route changed (headphones): continue from where the song was.
                        guard let self, self.playing else { return }
                        let at = self.positionMs()
                        self.playing = false
                        self.play(fromMs: Int(at), speed: self.speed)
                    }
                    self.ready = true
                    onReady()
                }
            } catch {
                DispatchQueue.main.async { self.failed = true }
            }
        }
    }

    func play(fromMs: Int, speed: Float) {
        guard ready, let file, let outFormat else { return }
        pause()
        AudioSession.activate()
        self.fromMs = Float(fromMs)
        self.speed = speed
        lastPosition = Float(fromMs)
        timePitch.rate = speed
        let rate = outFormat.sampleRate
        let gen: Int = queue.sync {
            generation += 1
            file.framePosition = min(file.length, AVAudioFramePosition(Double(fromMs) / 1000 * rate))
            return generation
        }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        queue.sync {
            for _ in 0..<3 { scheduleNext(gen) }
        }
        player.play()
        playing = true
    }

    func pause() {
        if playing { lastPosition = positionMs() }
        playing = false
        queue.sync { generation += 1 }
        player.stop()
        if engine.isRunning { engine.pause() }
    }

    func setVolume(_ v: Float) { player.volume = v }

    func positionMs() -> Float {
        guard playing,
              let nodeTime = player.lastRenderTime,
              let t = player.playerTime(forNodeTime: nodeTime),
              t.sampleRate > 0
        else { return lastPosition }
        return fromMs + Float(max(0, Double(t.sampleTime)) / t.sampleRate * 1000)
    }

    func release() { pause() }

    /// Reads, processes and queues the next chunk. Runs on `queue`.
    private func scheduleNext(_ gen: Int) {
        guard gen == generation, let file, let outFormat,
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: StemPlayer.chunk),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: StemPlayer.chunk)
        else { return }
        do {
            try file.read(into: input, frameCount: StemPlayer.chunk)
        } catch {
            return
        }
        let n = Int(input.frameLength)
        guard n > 0, let src = input.floatChannelData, let dst = output.floatChannelData else { return }
        let ch = Int(file.processingFormat.channelCount)
        let l = src[0]
        let r = ch > 1 ? src[1] : src[0]
        let outL = dst[0]
        let outR = dst[1]
        let mode: Mix = (mix == .instrumental && ch < 2) ? .original : mix
        for i in 0..<n {
            let a = l[i]
            let b = r[i]
            let m = (a + b) * 0.5
            let side = (a - b) * 0.5
            // Filters always run so switching modes is click-free.
            let low = bass.process(m)
            let voice = vocalLow.process(vocalHigh.process(m))
            switch mode {
            case .original:
                outL[i] = a
                outR[i] = b
            case .instrumental:
                outL[i] = side * 1.4 + low
                outR[i] = -side * 1.4 + low
            case .voice:
                let rest = m - voice
                outL[i] = voice * 1.2 + rest * 0.3 + side * 0.25
                outR[i] = voice * 1.2 + rest * 0.3 - side * 0.25
            }
        }
        output.frameLength = AVAudioFrameCount(n)
        player.scheduleBuffer(output, completionCallbackType: .dataConsumed) { [weak self] _ in
            self?.queue.async { self?.scheduleNext(gen) }
        }
    }
}
