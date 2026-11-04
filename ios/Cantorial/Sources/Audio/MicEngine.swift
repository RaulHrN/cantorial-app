import AVFoundation
import CantorialAtomics
import CantorialCore
import UIKit

/// Shared microphone analyser.
///
/// The audio thread decimates the input to about 22 kHz, detects the pitch and writes the
/// result into ring buffers that the screens read once per display frame. Nothing is allocated
/// per audio block. The microphone only runs while some screen holds the engine
/// (`acquire`/`release`), so it is idle everywhere else. Mirrors MicEngine of the Android app.
final class MicEngine {
    static let shared = MicEngine()

    static let window = 1024
    static let hop = 512
    static let capacity = 1024
    private static let minClarity: Float = 0.72

    /// Smoothed MIDI pitch per frame, NaN when silent or unpitched.
    let midi: UnsafeMutablePointer<Float>
    /// Input level per frame in dBFS.
    let levelDb: UnsafeMutablePointer<Float>
    /// Host time in nanoseconds when each frame was captured.
    let timeNs: UnsafeMutablePointer<Int64>
    private let frameCount: UnsafeMutablePointer<Int64>

    /// Rate of the analysed signal after decimation.
    private(set) var analysisRate: Float = 22050
    /// Frames quieter than this are treated as silence. Set from the sensitivity preference.
    var gateDb: Float = -50
    var a4: Float = 440
    private(set) var error: String?

    private var users = 0
    private var engine: AVAudioEngine?
    private var processor: Processor?
    private var observers: [NSObjectProtocol] = []
    private var configObserver: NSObjectProtocol?
    private var suspended = false

    private init() {
        let n = MicEngine.capacity
        midi = .allocate(capacity: n)
        midi.initialize(repeating: .nan, count: n)
        levelDb = .allocate(capacity: n)
        levelDb.initialize(repeating: -140, count: n)
        timeNs = .allocate(capacity: n)
        timeNs.initialize(repeating: 0, count: n)
        frameCount = .allocate(capacity: 1)
        frameCount.initialize(to: 0)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.users > 0 else { return }
            self.suspended = true
            self.stopEngine()
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.suspended else { return }
            self.suspended = false
            if self.users > 0 { self.startEngine() }
        })
    }

    /// Analysis frames written so far. Frame f lives at `index(f)`.
    var frames: Int64 { cantorial_load_acquire(frameCount) }

    var hopMs: Float { Float(MicEngine.hop) * 1000 / analysisRate }

    /// Age of the sound in a frame relative to its time stamp (half an analysis window).
    var latencyMs: Float { Float(MicEngine.window) * 500 / analysisRate }

    var active: Bool { users > 0 }

    func index(_ frame: Int64) -> Int { Int(frame % Int64(MicEngine.capacity)) }

    func latestMidi() -> Float {
        let f = frames
        return f == 0 ? .nan : midi[index(f - 1)]
    }

    func latestLevel() -> Float {
        let f = frames
        return f == 0 ? -100 : levelDb[index(f - 1)]
    }

    func acquire() {
        users += 1
        if users == 1 { startEngine() }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func release() {
        guard users > 0 else { return }
        users -= 1
        if users == 0 {
            stopEngine()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    fileprivate func publish(_ m: Float, _ db: Float, _ ns: Int64) {
        let f = cantorial_load_acquire(frameCount)
        let i = index(f)
        midi[i] = m
        levelDb[i] = db
        timeNs[i] = ns
        cantorial_store_release(frameCount, f + 1)
    }

    private func startEngine() {
        guard engine == nil else { return }
        error = nil
        AudioSession.activate()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "Microfone indisponível"
            return
        }
        let decimation = max(1, Int((format.sampleRate / 22050).rounded()))
        let rate = Float(format.sampleRate) / Float(decimation)
        analysisRate = rate
        let proc = Processor(owner: self, rate: rate, decimation: decimation, captureRate: format.sampleRate)
        let sink = AVAudioSinkNode { timestamp, count, buffers in
            proc.receive(timestamp, Int(count), buffers)
            return noErr
        }
        engine.attach(sink)
        engine.connect(input, to: sink, format: format)
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // A new route (headphones plugged in, Bluetooth) stops the engine: rebuild it.
            guard let self, self.users > 0 else { return }
            self.stopEngine()
            self.startEngine()
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            self.error = "Não foi possível abrir o microfone"
            return
        }
        self.engine = engine
        processor = proc
    }

    private func stopEngine() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
        engine?.stop()
        engine = nil
        processor = nil
    }

    /// Runs on the audio thread. Allocation-free.
    private final class Processor {
        unowned let owner: MicEngine
        let detector: PitchDetector
        var highPass: Biquad
        var smoother = PitchSmoother()
        let window: UnsafeMutablePointer<Float>
        var fill: Int
        let decimation: Int
        let nsPerSample: Double
        var acc: Float = 0
        var accCount = 0

        init(owner: MicEngine, rate: Float, decimation: Int, captureRate: Double) {
            self.owner = owner
            self.decimation = decimation
            nsPerSample = 1e9 / captureRate
            detector = PitchDetector(sampleRate: rate, windowSize: MicEngine.window, minFrequency: 60, maxFrequency: 1500)
            highPass = Biquad.highPass(sampleRate: rate, cutoff: 70)
            window = .allocate(capacity: MicEngine.window)
            window.initialize(repeating: 0, count: MicEngine.window)
            fill = MicEngine.window - MicEngine.hop
        }

        deinit { window.deallocate() }

        func receive(_ timestamp: UnsafePointer<AudioTimeStamp>, _ count: Int, _ list: UnsafePointer<AudioBufferList>) {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            guard let first = buffers.first, let data = first.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            let channels = Int(max(1, first.mNumberChannels))
            let host = timestamp.pointee.mHostTime
            let startNs = host != 0 ? HostClock.ns(host) : HostClock.nowNs()
            for i in 0..<count {
                acc += samples[i * channels]
                accCount += 1
                if accCount < decimation { continue }
                let x = highPass.process(acc / Float(decimation))
                acc = 0
                accCount = 0
                window[fill] = x
                fill += 1
                if fill == MicEngine.window {
                    analyse(startNs + Int64(Double(i + 1) * nsPerSample))
                    let keep = MicEngine.window - MicEngine.hop
                    for k in 0..<keep { window[k] = window[k + MicEngine.hop] }
                    fill = keep
                }
            }
        }

        private func analyse(_ ns: Int64) {
            let hz = detector.detect(UnsafePointer(window))
            let rms = detector.rms
            let db: Float = rms > 1e-7 ? 20 * log10(rms) : -140
            let voiced = hz > 0 && db > owner.gateDb && detector.clarity >= MicEngine.minClarity
            let m = smoother.push(voiced ? Pitch.hzToMidi(hz, a4: owner.a4) : .nan)
            owner.publish(m, db, ns)
        }
    }
}
