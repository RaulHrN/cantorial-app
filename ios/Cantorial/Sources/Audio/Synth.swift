import AVFoundation
import CantorialAtomics
import CantorialCore

/// A monophonic line for the `Synth`. Can be muted live through `enabled`.
final class SynthTrack {
    let starts: [Int]
    let durs: [Int]
    let midis: [Int]
    let gain: Float
    let bright: Bool
    /// Read by the audio thread; a plain flag is enough.
    var enabled = true

    init(_ notes: [NoteEvent], gain: Float, bright: Bool = false) {
        let sorted = notes.sorted { $0.startMs < $1.startMs }
        starts = sorted.map(\.startMs)
        durs = sorted.map(\.durMs)
        midis = sorted.map(\.midi)
        self.gain = gain
        self.bright = bright
    }

    convenience init(timed: [TimedNote], gain: Float, bright: Bool = false) {
        self.init(timed.map { NoteEvent($0.startMs, $0.durMs, $0.midi) }, gain: gain, bright: bright)
    }
}

/// Small synthesizer for reference tones and guide voices, rendered from wavetables in an
/// AVAudioSourceNode. Its rendered frame count doubles as the clock for exercises and songs
/// without audio. Mirrors Synth of the Android app.
final class Synth {
    var a4: Float = 440
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var renderer: Renderer?
    private var lastPosition: Float = 0
    private var configObserver: NSObjectProtocol?

    init() {
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.renderer != nil else { return }
            try? self.engine.start()
        }
    }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        engine.stop()
    }

    var isPlaying: Bool { renderer != nil }

    /// Current position in song time (ms).
    func positionMs() -> Float { renderer?.positionMs() ?? lastPosition }

    /// Plays `tracks` from `fromMs`; silence after `untilMs` (song time).
    func start(_ tracks: [SynthTrack], from fromMs: Float, speed: Float = 1, until untilMs: Float = .greatestFiniteMagnitude) {
        stop()
        AudioSession.activate()
        var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate <= 0 { rate = 48000 }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        let r = Renderer(tracks: tracks, fromMs: Double(fromMs), speed: Double(speed), untilMs: Double(untilMs), sampleRate: rate, a4: a4)
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let data = list.first?.mData else { return noErr }
            r.render(Int(frameCount), data.assumingMemoryBound(to: Float.self))
            for k in 1..<max(1, list.count) {
                if let other = list[k].mData { other.copyMemory(from: data, byteCount: Int(frameCount) * MemoryLayout<Float>.size) }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.detach(source)
            return
        }
        node = source
        renderer = r
        lastPosition = fromMs
    }

    /// Short preview of a single note.
    func preview(_ midi: Int) {
        start([SynthTrack([NoteEvent(0, 450, midi)], gain: 0.3)], from: 0, until: 700)
    }

    func stop() {
        if let r = renderer { lastPosition = r.positionMs() }
        renderer = nil
        engine.stop()
        if let n = node {
            engine.disconnectNodeOutput(n)
            engine.detach(n)
        }
        node = nil
    }

    private static let tableSize = 2048
    private static let attackMs = 25.0
    private static let releaseMs = 90.0
    fileprivate static let soft = wavetable([1, 0.18, 0.06])
    fileprivate static let brightTable = wavetable([1, 0.45, 0.28, 0.14, 0.08, 0.04])

    private static func wavetable(_ harmonics: [Double]) -> UnsafeMutablePointer<Float> {
        let n = tableSize
        let t = UnsafeMutablePointer<Float>.allocate(capacity: n + 1)
        var peak: Float = 0
        for i in 0..<n {
            var v = 0.0
            for (h, a) in harmonics.enumerated() { v += a * sin(2.0 * Double.pi * Double(h + 1) * Double(i) / Double(n)) }
            t[i] = Float(v)
            peak = max(peak, abs(t[i]))
        }
        for i in 0..<n { t[i] /= peak }
        t[n] = t[0]
        return t
    }

    /// Renders on the audio thread. Stateless across blocks apart from the frame counter:
    /// the phase of each note comes from the time elapsed since its start.
    private final class Renderer {
        let tracks: [SynthTrack]
        let fromMs: Double
        let speed: Double
        let untilMs: Double
        let sampleRate: Double
        let a4: Float
        let latencyMs: Double
        let frame: UnsafeMutablePointer<Int64>

        init(tracks: [SynthTrack], fromMs: Double, speed: Double, untilMs: Double, sampleRate: Double, a4: Float) {
            self.tracks = tracks
            self.fromMs = fromMs
            self.speed = speed
            self.untilMs = untilMs
            self.sampleRate = sampleRate
            self.a4 = a4
            latencyMs = AudioSession.outputLatencyMs
            frame = .allocate(capacity: 1)
            frame.initialize(to: 0)
        }

        deinit { frame.deallocate() }

        func positionMs() -> Float {
            let rendered = Double(cantorial_load_acquire(frame)) / sampleRate * 1000
            return Float(fromMs + max(0, rendered - latencyMs) * speed)
        }

        func render(_ n: Int, _ out: UnsafeMutablePointer<Float>) {
            for i in 0..<n { out[i] = 0 }
            let f = cantorial_load_acquire(frame)
            let msPerFrame = 1000.0 / sampleRate * speed
            let t0 = fromMs + Double(f) * msPerFrame
            if t0 <= untilMs {
                for tr in tracks where tr.enabled { render(tr, t0, msPerFrame, n, out) }
                for i in 0..<n { out[i] = min(max(out[i], -1), 1) }
            }
            cantorial_store_release(frame, f + Int64(n))
        }

        private func render(_ tr: SynthTrack, _ t0: Double, _ msPerFrame: Double, _ n: Int, _ out: UnsafeMutablePointer<Float>) {
            let t1 = t0 + Double(n) * msPerFrame
            // Last note that starts before the end of this block.
            var lo = 0
            var hi = tr.starts.count - 1
            var last = -1
            while lo <= hi {
                let mid = (lo + hi) >> 1
                if Double(tr.starts[mid]) < t1 {
                    last = mid
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
            let table = tr.bright ? Synth.brightTable : Synth.soft
            let size = Double(Synth.tableSize)
            var k = last
            var checked = 0
            while k >= 0 && checked < 6 {
                let start = Double(tr.starts[k])
                let dur = Double(tr.durs[k])
                if start + dur + Synth.releaseMs >= t0 {
                    let hz = Double(Pitch.midiToHz(Float(tr.midis[k]), a4: a4))
                    for i in 0..<n {
                        let rel = t0 + Double(i) * msPerFrame - start
                        if rel < 0 || rel > dur + Synth.releaseMs { continue }
                        var env = min(1.0, rel / Synth.attackMs) * (0.78 + 0.22 * exp(-rel / 300.0))
                        if rel > dur { env *= 1.0 - (rel - dur) / Synth.releaseMs }
                        let cycles = hz * rel / 1000.0 / speed
                        let pos = (cycles - cycles.rounded(.down)) * size
                        let idx = Int(pos)
                        let frac = Float(pos - Double(idx))
                        let s = table[idx] + (table[idx + 1] - table[idx]) * frac
                        out[i] += s * Float(env) * tr.gain
                    }
                }
                checked += 1
                k -= 1
            }
        }
    }
}
