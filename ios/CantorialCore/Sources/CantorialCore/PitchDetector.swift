import Foundation

/// Monophonic pitch detector based on the McLeod Pitch Method (MPM), with an FFT based
/// autocorrelation. All buffers are allocated once, so the audio thread never allocates.
public final class PitchDetector {
    public let sampleRate: Float
    public let windowSize: Int
    private let peakThreshold: Float
    private let fftSize: Int
    private let fft: FFT
    private let re: UnsafeMutablePointer<Float>
    private let im: UnsafeMutablePointer<Float>
    private let x: UnsafeMutablePointer<Float>
    private let minTau: Int
    private let maxTau: Int
    private let nsdf: UnsafeMutablePointer<Float>
    private var peaks = [Int](repeating: 0, count: 64)

    /// Periodicity of the last analysed window, 0...1. Above ~0.8 means a clear tone.
    public private(set) var clarity: Float = 0
    /// Root mean square level of the last analysed window (after DC removal).
    public private(set) var rms: Float = 0

    public init(sampleRate: Float, windowSize: Int, minFrequency: Float = 60, maxFrequency: Float = 1500, peakThreshold: Float = 0.9) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.peakThreshold = peakThreshold
        var size = 1
        while size < windowSize * 2 { size <<= 1 }
        fftSize = size
        fft = FFT(size: size)
        re = .allocate(capacity: size)
        im = .allocate(capacity: size)
        x = .allocate(capacity: windowSize)
        minTau = max(2, Int((sampleRate / maxFrequency).rounded(.down)))
        maxTau = min(windowSize / 2, Int((sampleRate / minFrequency).rounded(.up)))
        nsdf = .allocate(capacity: maxTau + 2)
        nsdf.initialize(repeating: 0, count: maxTau + 2)
    }

    deinit {
        re.deallocate()
        im.deallocate()
        x.deallocate()
        nsdf.deallocate()
    }

    /// Fundamental frequency in Hz of `windowSize` samples starting at `input`, or -1.
    public func detect(_ input: UnsafePointer<Float>) -> Float {
        clarity = 0
        var sum: Double = 0
        for i in 0..<windowSize { sum += Double(input[i]) }
        let mean = Float(sum / Double(windowSize))
        var energy: Double = 0
        for i in 0..<windowSize {
            let v = input[i] - mean
            x[i] = v
            energy += Double(v * v)
        }
        rms = Float((energy / Double(windowSize)).squareRoot())
        if energy < 1e-10 { return -1 }

        // Autocorrelation r(tau) = IFFT(|FFT(x)|^2), zero padded against circular wrap.
        for i in 0..<fftSize {
            re[i] = i < windowSize ? x[i] : 0
            im[i] = 0
        }
        fft.forward(re, im)
        for k in 0..<fftSize {
            re[k] = re[k] * re[k] + im[k] * im[k]
            im[k] = 0
        }
        // The power spectrum is real and even: a second forward FFT equals N * IFFT.
        fft.forward(re, im)
        let scale = 1.0 / Double(fftSize)

        var m = 2.0 * energy
        for tau in 0...(maxTau + 1) {
            nsdf[tau] = m > 1e-12 ? Float(2.0 * Double(re[tau]) * scale / m) : 0
            let a = Double(x[tau])
            let b = Double(x[windowSize - 1 - tau])
            m -= a * a + b * b
        }

        // Key maxima: the top of each positive lobe after the first zero crossing.
        var count = 0
        var best: Float = 0
        var tau = 1
        while tau <= maxTau && nsdf[tau] > 0 { tau += 1 }
        while tau <= maxTau && count < peaks.count {
            while tau <= maxTau && nsdf[tau] <= 0 { tau += 1 }
            if tau > maxTau { break }
            var peak = tau
            while tau <= maxTau && nsdf[tau] > 0 {
                if nsdf[tau] > nsdf[peak] { peak = tau }
                tau += 1
            }
            if peak >= minTau {
                peaks[count] = peak
                count += 1
                if nsdf[peak] > best { best = nsdf[peak] }
            }
        }
        if count == 0 { return -1 }

        let threshold = peakThreshold * best
        var chosen = peaks[0]
        for i in 0..<count where nsdf[peaks[i]] >= threshold {
            chosen = peaks[i]
            break
        }

        let a = nsdf[chosen - 1]
        let b = nsdf[chosen]
        let c = nsdf[chosen + 1]
        let denom = a - 2 * b + c
        var delta: Float = 0
        var peakValue = b
        if denom < 0 {
            delta = 0.5 * (a - c) / denom
            if abs(delta) <= 1 { peakValue = b - 0.25 * (a - c) * delta } else { delta = 0 }
        }
        clarity = min(peakValue, 1)
        return sampleRate / (Float(chosen) + delta)
    }

    /// Convenience for tests and offline use.
    public func detect(_ input: [Float], offset: Int = 0) -> Float {
        input.withUnsafeBufferPointer { detect($0.baseAddress! + offset) }
    }
}

/// Second order IIR filter (RBJ cookbook).
public struct Biquad {
    private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    private init(_ b0: Double, _ b1: Double, _ b2: Double, _ a1: Double, _ a2: Double) {
        self.b0 = Float(b0); self.b1 = Float(b1); self.b2 = Float(b2); self.a1 = Float(a1); self.a2 = Float(a2)
    }

    public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }

    public mutating func reset() {
        x1 = 0; x2 = 0; y1 = 0; y2 = 0
    }

    public static func highPass(sampleRate: Float, cutoff: Float, q: Double = 0.7071) -> Biquad {
        let w0 = 2.0 * Double.pi * Double(cutoff) / Double(sampleRate)
        let cw = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        return Biquad((1 + cw) / 2 / a0, -(1 + cw) / a0, (1 + cw) / 2 / a0, -2 * cw / a0, (1 - alpha) / a0)
    }

    public static func lowPass(sampleRate: Float, cutoff: Float, q: Double = 0.7071) -> Biquad {
        let w0 = 2.0 * Double.pi * Double(cutoff) / Double(sampleRate)
        let cw = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        return Biquad((1 - cw) / 2 / a0, (1 - cw) / a0, (1 - cw) / 2 / a0, -2 * cw / a0, (1 - alpha) / a0)
    }
}

/// Median-of-three smoothing for a stream of MIDI pitches (NaN = silence).
public struct PitchSmoother {
    private var recent: (Float, Float, Float) = (0, 0, 0)
    private var count = 0
    private var silent = 0

    public init() {}

    public mutating func push(_ midi: Float) -> Float {
        if midi.isNaN {
            silent += 1
            if silent >= 3 { count = 0 }
            return .nan
        }
        silent = 0
        recent = (recent.1, recent.2, midi)
        if count < 3 { count += 1 }
        if count < 3 { return midi }
        let (a, b, c) = recent
        return max(min(a, b), min(max(a, b), c))
    }
}
