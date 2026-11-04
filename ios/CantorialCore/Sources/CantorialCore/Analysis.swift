import Foundation

/// Offline pitch tracking: feed mono samples (already at `sampleRate`) and get one MIDI value
/// per hop. Used for recordings of the user singing.
public final class TrackAnalyzer {
    public let sampleRate: Float
    public let window: Int
    public let hop: Int
    private let minClarity: Float
    private let a4: Float
    private let detector: PitchDetector
    private var filter: Biquad?
    private var buf: [Float]
    private var fill = 0
    private var pitches: [Float] = []
    private var levelsDb: [Float] = []

    public init(sampleRate: Float, window: Int = 1024, hop: Int = 512, minClarity: Float = 0.8, highPassHz: Float = 0, a4: Float = 440) {
        self.sampleRate = sampleRate
        self.window = window
        self.hop = hop
        self.minClarity = minClarity
        self.a4 = a4
        detector = PitchDetector(sampleRate: sampleRate, windowSize: window, minFrequency: 65, maxFrequency: 1300)
        filter = highPassHz > 0 ? Biquad.highPass(sampleRate: sampleRate, cutoff: highPassHz) : nil
        buf = [Float](repeating: 0, count: window)
        pitches.reserveCapacity(4096)
        levelsDb.reserveCapacity(4096)
    }

    public var hopMs: Float { Float(hop) * 1000 / sampleRate }

    /// Time of the centre of the first analysis window.
    public var firstFrameMs: Float { Float(window) * 500 / sampleRate }

    public var frames: Int { pitches.count }

    public func push(_ sample: Float) {
        var x = sample
        if filter != nil { x = filter!.process(sample) }
        buf[fill] = x
        fill += 1
        if fill == window {
            let hz = detector.detect(buf)
            let rms = detector.rms
            levelsDb.append(rms > 1e-7 ? 20 * log10(rms) : -140)
            pitches.append(hz > 0 && detector.clarity >= minClarity ? Pitch.hzToMidi(hz, a4: a4) : .nan)
            let keep = window - hop
            for i in 0..<keep { buf[i] = buf[i + hop] }
            fill = keep
        }
    }

    /// Level of each frame in dBFS.
    public func levels() -> [Float] { levelsDb }

    /// The pitch track with quiet frames removed. A frame is kept when it is louder than
    /// `absoluteGateDb` and within `relativeGateDb` of the loud parts of the recording.
    public func track(relativeGateDb: Float = 30, absoluteGateDb: Float = -55) -> [Float] {
        let n = pitches.count
        if n == 0 { return [] }
        let sorted = levelsDb.sorted()
        let loud = sorted[Int(Float(n - 1) * 0.95)]
        let gate = max(absoluteGateDb, loud - relativeGateDb)
        return (0..<n).map { levelsDb[$0] >= gate ? pitches[$0] : .nan }
    }
}
