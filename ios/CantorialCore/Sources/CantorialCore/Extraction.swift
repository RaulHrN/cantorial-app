import Foundation

/// Finds the sung melody inside a music mix, telling the voice apart from the instruments.
///
/// 1. Stereo STFT. Each frequency bin is weighted by how similar the two channels are there
///    (lead vocals sit in the centre) and by a vocal band filter.
/// 2. Harmonic summation turns spectral peaks into a pitch salience function (10-cent bins).
/// 3. Salience peaks are linked into pitch contours.
/// 4. Contours are described: salience, pitch, vibrato, natural pitch movement, how fast the
///    sound dies away, where it sits in the stereo image and how exactly it lands on the
///    tempered grid. Non-vocal contours, isolated stray notes and octave duplicates are dropped,
///    and the melody is the best remaining contour in each frame.
///
/// Mirrors MelodyExtractor of the Android app.
public final class MelodyExtractor {
    public struct Result {
        /// MIDI pitch per frame, NaN where nobody sings.
        public let track: [Float]
        /// Level of each frame in dB (vocal-weighted).
        public let levels: [Float]
        public let hopMs: Float
        public let firstFrameMs: Float
        /// Fraction of frames with a voice.
        public let voicedRatio: Float
    }

    public static let window = 1024
    public static let hop = 512
    private static let fftSize = 2048
    private static let maxPeaks = 48
    private static let harmonics = 8
    private static let alpha: Float = 0.8
    private static let minHz: Float = 55
    private static let minMidi: Float = 33
    private static let salBins = 600
    private static let peaksPerFrame = 5
    private static let maxStep: Float = 0.9
    private static let maxGap = 4
    private static let minLength = 5
    private static let seedRatio: Float = 0.6
    private static let ghosts: [Float] = [12, 19, 24]

    public let sampleRate: Float
    private let a4: Float
    private let fft = FFT(size: MelodyExtractor.fftSize)
    private let re: UnsafeMutablePointer<Float> = .allocate(capacity: MelodyExtractor.fftSize)
    private let im: UnsafeMutablePointer<Float> = .allocate(capacity: MelodyExtractor.fftSize)
    private let win: UnsafeMutablePointer<Float> = .allocate(capacity: MelodyExtractor.window)
    private var bufL = [Float](repeating: 0, count: MelodyExtractor.window)
    private var bufR = [Float](repeating: 0, count: MelodyExtractor.window)
    private var fill = 0
    private let bins = MelodyExtractor.fftSize / 2
    private var mag = [Float](repeating: 0, count: MelodyExtractor.fftSize / 2 + 1)
    private var centreAt = [Float](repeating: 0, count: MelodyExtractor.fftSize / 2 + 1)
    private var bandWeight = [Float](repeating: 0, count: MelodyExtractor.fftSize / 2 + 1)
    private var salience = [Float](repeating: 0, count: MelodyExtractor.salBins)
    private var peakFreq = [Float](repeating: 0, count: MelodyExtractor.maxPeaks)
    private var peakAmp = [Float](repeating: 0, count: MelodyExtractor.maxPeaks)
    private var peakBin = [Int](repeating: 0, count: MelodyExtractor.maxPeaks)
    private var refinedCentre: Float = 1

    // Per frame: `peaksPerFrame` (pitch, salience, centre) slots.
    private var framePitch: [Float] = []
    private var frameSal: [Float] = []
    private var frameCentre: [Float] = []
    private var levels: [Float] = []
    private var frames = 0

    public var hopMs: Float { Float(MelodyExtractor.hop) * 1000 / sampleRate }

    public init(sampleRate: Float, a4: Float = 440) {
        self.sampleRate = sampleRate
        self.a4 = a4
        re.initialize(repeating: 0, count: MelodyExtractor.fftSize)
        im.initialize(repeating: 0, count: MelodyExtractor.fftSize)
        let n = MelodyExtractor.window
        win.initialize(repeating: 0, count: n)
        for i in 0..<n {
            let x = 2.0 * Double.pi * Double(i) / Double(n - 1)
            win[i] = Float(0.5 - 0.5 * cos(x))
        }
        for k in 0...bins {
            bandWeight[k] = MelodyExtractor.weight(Float(k) * sampleRate / Float(MelodyExtractor.fftSize))
        }
        framePitch.reserveCapacity(8192)
        frameSal.reserveCapacity(8192)
        frameCentre.reserveCapacity(8192)
    }

    deinit {
        re.deallocate()
        im.deallocate()
        win.deallocate()
    }

    /// Emphasises the vocal band, damping bass and cymbals.
    private static func weight(_ hz: Float) -> Float {
        if hz < 60 { return 0.05 }
        if hz < 180 { return 0.05 + 0.95 * (hz - 60) / 120 }
        if hz < 4000 { return 1 }
        if hz < 8000 { return 1 - 0.8 * (hz - 4000) / 4000 }
        return 0.2
    }

    public func push(_ left: Float, _ right: Float) {
        bufL[fill] = left
        bufR[fill] = right
        fill += 1
        if fill == MelodyExtractor.window {
            analyse()
            let h = MelodyExtractor.hop
            let keep = MelodyExtractor.window - h
            for i in 0..<keep {
                bufL[i] = bufL[i + h]
                bufR[i] = bufR[i + h]
            }
            fill = keep
        }
    }

    private func analyse() {
        let n = MelodyExtractor.window
        let size = MelodyExtractor.fftSize
        // Left in the real part, right in the imaginary part: one FFT gives both spectra.
        for i in 0..<size {
            if i < n {
                re[i] = bufL[i] * win[i]
                im[i] = bufR[i] * win[i]
            } else {
                re[i] = 0
                im[i] = 0
            }
        }
        fft.forward(re, im)

        var energy = 0.0
        var maxMag: Float = 0
        mag[0] = 0
        mag[bins] = 0
        for k in 1..<bins {
            let lr = (re[k] + re[size - k]) * 0.5
            let li = (im[k] - im[size - k]) * 0.5
            let rr = (im[k] + im[size - k]) * 0.5
            let ri = (re[size - k] - re[k]) * 0.5
            let pl = lr * lr + li * li
            let pr = rr * rr + ri * ri
            let similarity = 2 * (lr * rr + li * ri) / (pl + pr + 1e-12)
            let centre = max(0, similarity)
            centreAt[k] = centre
            let mr = lr + rr
            let mi = li + ri
            let pan: Float = 0.25 + 0.75 * centre * centre
            let m: Float = (mr * mr + mi * mi).squareRoot() * 0.5 * pan * bandWeight[k]
            mag[k] = m
            energy += Double(m * m)
            if m > maxMag { maxMag = m }
        }
        let db: Float = energy > 1e-14 ? Float(10 * log10(energy / Double(n))) : -140
        levels.append(db)

        let start = framePitch.count
        if db > -75 && maxMag > 0 {
            let count = peaks(maxMag)
            salienceFrom(count)
            pickSaliencePeaks(count)
        }
        // Pad the frame to a fixed number of slots.
        while framePitch.count < start + MelodyExtractor.peaksPerFrame {
            framePitch.append(.nan)
            frameSal.append(0)
            frameCentre.append(0)
        }
        frames += 1
    }

    /// Spectral peaks above -40 dB of the frame maximum, with parabolic interpolation.
    private func peaks(_ maxMag: Float) -> Int {
        let size = Float(MelodyExtractor.fftSize)
        let floor = maxMag * 0.01
        let kMin = max(2, Int(50 * size / sampleRate))
        let kMax = min(bins - 2, Int(5000 * size / sampleRate))
        var count = 0
        if kMin > kMax { return 0 }
        for k in kMin...kMax {
            let m = mag[k]
            if m > floor && m > mag[k - 1] && m >= mag[k + 1] {
                let a = log(mag[k - 1] + 1e-12)
                let b = log(m)
                let c = log(mag[k + 1] + 1e-12)
                let denom = a - 2 * b + c
                let delta: Float = denom < 0 ? min(max(0.5 * (a - c) / denom, -0.5), 0.5) : 0
                let amp = exp(b - 0.25 * (a - c) * delta)
                let freq = (Float(k) + delta) * sampleRate / size
                if count < MelodyExtractor.maxPeaks {
                    peakFreq[count] = freq
                    peakAmp[count] = amp
                    peakBin[count] = k
                    count += 1
                } else {
                    // Replace the weakest stored peak.
                    var weakest = 0
                    for j in 1..<MelodyExtractor.maxPeaks where peakAmp[j] < peakAmp[weakest] { weakest = j }
                    if amp > peakAmp[weakest] {
                        peakFreq[weakest] = freq
                        peakAmp[weakest] = amp
                        peakBin[weakest] = k
                    }
                }
            }
        }
        return count
    }

    /// Harmonic summation: each peak votes for the fundamentals it could be a harmonic of.
    private func salienceFrom(_ count: Int) {
        for i in 0..<MelodyExtractor.salBins { salience[i] = 0 }
        for p in 0..<count {
            let f = peakFreq[p]
            let a = peakAmp[p]
            var weight: Float = 1
            for h in 1...MelodyExtractor.harmonics {
                let f0 = f / Float(h)
                if f0 < MelodyExtractor.minHz { break }
                let b = (Pitch.hzToMidi(f0, a4: a4) - MelodyExtractor.minMidi) * 10
                if b < Float(MelodyExtractor.salBins + 10) {
                    let centre = roundInt(b)
                    for d in -10...10 {
                        let bin = centre + d
                        if bin < 0 || bin >= MelodyExtractor.salBins { continue }
                        let dist = abs(Float(bin) - b) / 10
                        if dist >= 1 { continue }
                        let g = cos(Float.pi / 2 * dist)
                        salience[bin] += a * weight * g * g
                    }
                }
                weight *= MelodyExtractor.alpha
            }
        }
    }

    private func pickSaliencePeaks(_ peakCount: Int) {
        let slotsCount = MelodyExtractor.peaksPerFrame
        var best: Float = 0
        for v in salience where v > best { best = v }
        guard best > 0 else { return }
        // Keep the strongest local maxima above 25% of the frame maximum.
        var slots = [Float](repeating: .nan, count: slotsCount)
        var vals = [Float](repeating: 0, count: slotsCount)
        for b in 1..<(MelodyExtractor.salBins - 1) {
            let v = salience[b]
            if v < 0.25 * best || v <= salience[b - 1] || v < salience[b + 1] { continue }
            var weakest = 0
            for j in 1..<slotsCount where vals[j] < vals[weakest] { weakest = j }
            if v > vals[weakest] {
                let a = salience[b - 1]
                let c = salience[b + 1]
                let denom = a - 2 * v + c
                let delta: Float = denom < 0 ? min(max(0.5 * (a - c) / denom, -0.5), 0.5) : 0
                slots[weakest] = MelodyExtractor.minMidi + (Float(b) + delta) / 10
                vals[weakest] = v
            }
        }
        for j in 0..<slotsCount {
            if slots[j].isNaN {
                framePitch.append(.nan)
                frameCentre.append(0)
            } else {
                framePitch.append(refine(slots[j], peakCount))
                frameCentre.append(refinedCentre)
            }
            frameSal.append(vals[j])
        }
    }

    /// Re-measures the pitch from the partials actually present (f = h * f0), and how
    /// centred the source is in the stereo image (1 = centre or mono).
    private func refine(_ midi: Float, _ peakCount: Int) -> Float {
        let f0 = Pitch.midiToHz(midi, a4: a4)
        var num: Float = 0
        var den: Float = 0
        var centre: Float = 0
        for h in 1...6 {
            let target = f0 * Float(h)
            var bestA: Float = 0
            var bestF: Float = 0
            for p in 0..<peakCount {
                let f = peakFreq[p]
                if f > target * 0.977 && f < target * 1.0235 && peakAmp[p] > bestA {
                    bestA = peakAmp[p]
                    bestF = f
                }
            }
            if bestA > 0 {
                num += bestA * bestF / Float(h)
                den += bestA
                let bin = min(max(roundInt(bestF * Float(MelodyExtractor.fftSize) / sampleRate), 0), bins)
                centre += bestA * centreAt[bin]
            }
        }
        refinedCentre = den > 0 ? centre / den : 1
        return den > 0 ? Pitch.hzToMidi(num / den, a4: a4) : midi
    }

    private final class Contour {
        let start: Int
        var pitch: [Float] = []
        var sal: [Float] = []
        var centre: [Float] = []
        var meanSal: Float = 0
        var totalSal: Float = 0
        var meanPitch: Float = 0
        var vocal: Float = 0
        var vibrato = false
        var stereoCentre: Float = 1
        var decayDbPerS: Float = 0
        var dev: [Float] = []
        var removed = false

        init(start: Int) { self.start = start }

        var end: Int { start + pitch.count - 1 }

        func pitchAt(_ frame: Int) -> Float {
            let i = frame - start
            return (i < 0 || i >= pitch.count) ? .nan : pitch[i]
        }
    }

    public func finish() -> Result {
        let contours = track()
        describe(contours)
        select(contours)
        var melody = [Float](repeating: .nan, count: frames)
        var score = [Float](repeating: 0, count: frames)
        for c in contours where !c.removed {
            let s = c.meanSal * (1 + 0.8 * c.vocal)
            for f in c.start...c.end {
                let p = c.pitchAt(f)
                if !p.isNaN && s > score[f] {
                    score[f] = s
                    melody[f] = p
                }
            }
        }
        let voiced = melody.filter { !$0.isNaN }.count
        return Result(
            track: melody,
            levels: levels,
            hopMs: hopMs,
            firstFrameMs: Float(MelodyExtractor.window) * 500 / sampleRate,
            voicedRatio: frames == 0 ? 0 : Float(voiced) / Float(frames)
        )
    }

    /// Links salience peaks into pitch contours. Only strong peaks start a contour; it then
    /// grows forwards and backwards through any peak that continues its pitch.
    private func track() -> [Contour] {
        let p = MelodyExtractor.peaksPerFrame
        let total = frames * p
        var assigned = [Bool](repeating: false, count: total)
        var frameMax = [Float](repeating: 0, count: frames)
        for i in 0..<total where frameSal[i] > frameMax[i / p] { frameMax[i / p] = frameSal[i] }
        let seeds = (0..<total)
            .filter { !framePitch[$0].isNaN && frameSal[$0] >= MelodyExtractor.seedRatio * frameMax[$0 / p] }
            .sorted { frameSal[$0] > frameSal[$1] }

        func follow(_ from: Int, _ pitch0: Float, _ step: Int) -> (pitch: [Float], sal: [Float], centre: [Float]) {
            var out: [Float] = []
            var sal: [Float] = []
            var cen: [Float] = []
            var pitch = pitch0
            var f = from
            var gap = 0
            while true {
                f += step
                if f < 0 || f >= frames { break }
                var best = -1
                var bestD = MelodyExtractor.maxStep
                for j in 0..<p {
                    let i = f * p + j
                    if assigned[i] || framePitch[i].isNaN { continue }
                    let d = abs(framePitch[i] - pitch)
                    if d < bestD {
                        bestD = d
                        best = i
                    }
                }
                if best < 0 {
                    gap += 1
                    if gap > MelodyExtractor.maxGap { break }
                    out.append(.nan)
                    sal.append(0)
                    cen.append(0)
                    continue
                }
                gap = 0
                assigned[best] = true
                pitch = framePitch[best]
                out.append(pitch)
                sal.append(frameSal[best])
                cen.append(frameCentre[best])
            }
            // Drop the unvoiced tail left by the gap allowance.
            while let last = out.last, last.isNaN {
                out.removeLast()
                sal.removeLast()
                cen.removeLast()
            }
            return (out, sal, cen)
        }

        var contours: [Contour] = []
        for seed in seeds where !assigned[seed] {
            assigned[seed] = true
            let f0 = seed / p
            let fwd = follow(f0, framePitch[seed], 1)
            let back = follow(f0, framePitch[seed], -1)
            let c = Contour(start: f0 - back.pitch.count)
            c.pitch = Array(back.pitch.reversed())
            c.pitch.append(framePitch[seed])
            c.pitch.append(contentsOf: fwd.pitch)
            c.sal = Array(back.sal.reversed())
            c.sal.append(frameSal[seed])
            c.sal.append(contentsOf: fwd.sal)
            c.centre = Array(back.centre.reversed())
            c.centre.append(frameCentre[seed])
            c.centre.append(contentsOf: fwd.centre)
            if c.pitch.filter({ !$0.isNaN }).count >= MelodyExtractor.minLength { contours.append(c) }
        }
        return contours
    }

    /// Salience statistics and how voice-like each contour is.
    private func describe(_ contours: [Contour]) {
        for c in contours {
            var n = 0
            var sum: Float = 0
            var pitchSum: Float = 0
            var centreSum: Float = 0
            for i in 0..<c.pitch.count where !c.pitch[i].isNaN {
                n += 1
                sum += c.sal[i]
                pitchSum += c.pitch[i]
                centreSum += c.sal[i] * c.centre[i]
            }
            c.totalSal = sum
            c.meanSal = sum / Float(max(n, 1))
            c.meanPitch = pitchSum / Float(max(n, 1))
            c.stereoCentre = sum > 0 ? centreSum / sum : 1
            c.decayDbPerS = decay(c)

            // Detrend with a ~200 ms moving average and look at what is left.
            let len = c.pitch.count
            var dev = [Float](repeating: .nan, count: len)
            for i in 0..<len where !c.pitch[i].isNaN {
                var s: Float = 0
                var k = 0
                for j in max(0, i - 4)...min(len - 1, i + 4) where !c.pitch[j].isNaN {
                    s += c.pitch[j]
                    k += 1
                }
                dev[i] = (c.pitch[i] - s / Float(k)) * 100
            }
            var sq: Float = 0
            var m = 0
            for v in dev where !v.isNaN {
                sq += v * v
                m += 1
            }
            let wobble = m > 0 ? (sq / Float(m)).squareRoot() : 0
            // Vibrato is a regular oscillation: look for a clear periodogram peak at 3.5-8.5 Hz.
            var purity: Float = 0
            if len >= 12 && sq > 0 {
                var r = 3.5
                while r <= 8.5 {
                    var xc = 0.0
                    var xs = 0.0
                    for i in 0..<len where !dev[i].isNaN {
                        let ph = 2.0 * Double.pi * r * Double(i) * Double(hopMs) / 1000.0
                        xc += Double(dev[i]) * cos(ph)
                        xs += Double(dev[i]) * sin(ph)
                    }
                    let pw = Float(2.0 * (xc * xc + xs * xs) / (Double(m) * Double(sq)))
                    if pw > purity { purity = pw }
                    r += 0.25
                }
            }
            let vibrato = purity >= 0.45 && wobble >= 7 && wobble <= 90
            let seconds = Float(len) * hopMs / 1000
            // Plain flat lines (keys, guitars, pads) score 0; lively voice-like lines up to 2.
            let liveliness: Float = min(max((wobble - 3) / 12, 0), vibrato ? 1 : 0.7)
            var vocal: Float = (vibrato ? 1 : 0) + liveliness
            // Struck and plucked sounds die away; a voice sustains.
            if c.decayDbPerS < -12 {
                vocal -= min(1.5, (-c.decayDbPerS - 12) / 8 + 0.5)
            } else if !vibrato && c.decayDbPerS > -6 && c.stereoCentre >= 0.9 && len >= 8 && seconds <= 2.5 && wobble >= 4 {
                // A sung note: sustained, centred, alive.
                vocal += 0.25
            }
            // Long flat drones (pads, organ, bass held under a chord) are accompaniment.
            if !vibrato && seconds > 2.5 { vocal -= 0.6 }
            // Lead vocals sit in the centre; a panned line is an instrument.
            if c.stereoCentre < 0.85 { vocal -= (0.85 - c.stereoCentre) * 6 }
            c.vocal = vocal
            c.vibrato = vibrato
            c.dev = dev
        }
    }

    /// Level slope over the contour in dB per second, ignoring the attack and the release.
    private func decay(_ c: Contour) -> Float {
        var n = 0.0
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for i in stride(from: 2, to: c.pitch.count - 3, by: 1) {
            if c.pitch[i].isNaN || c.sal[i] <= 0 { continue }
            let x = Double(i) * Double(hopMs) / 1000
            let y = 20 * log10(Double(c.sal[i]))
            n += 1
            sx += x; sy += y; sxx += x * x; sxy += x * y
        }
        if n < 6 { return 0 }
        let den = n * sxx - sx * sx
        return den <= 1e-12 ? 0 : Float((n * sxy - sx * sy) / den)
    }

    /// Voicing detection and octave-error removal, then leaves the melody contours.
    private func select(_ contours: [Contour]) {
        // Keys and frets land exactly on the tempered grid; singers drift around it.
        let tuning = tuningOffset(contours)
        for c in contours where !c.vibrato {
            let off = abs(gridDistance(c.meanPitch - tuning)) * 100
            if off < 3 { c.vocal -= 0.15 } else if off > 12 { c.vocal += 0.15 }
        }
        for c in contours where c.meanPitch < 42 || c.meanPitch > 86 || c.vocal < 0.35 {
            // Outside the singing range, or an instrument-like line: not the voice.
            c.removed = true
        }
        let alive = contours.filter { !$0.removed }
        if alive.isEmpty { return }
        let mean = alive.map { $0.meanSal }.reduce(0, +) / Float(alive.count)
        let std = (alive.map { ($0.meanSal - mean) * ($0.meanSal - mean) }.reduce(0, +) / Float(alive.count)).squareRoot()
        for c in alive {
            let threshold = c.vocal >= 1 ? mean - 0.9 * std : mean - 0.3 * std
            if c.meanSal < threshold { c.removed = true }
        }
        // Harmonic ghosts move in sync with their source: keep the strongest of the family.
        let kept = contours.filter { !$0.removed }
        for a in kept {
            for b in kept where a !== b && !a.removed && !b.removed && overlaps(a, b) {
                let diff = abs(a.meanPitch - b.meanPitch)
                if !MelodyExtractor.ghosts.contains(where: { abs(diff - $0) < 0.6 }) { continue }
                if correlation(a, b) < 0.5 { continue }
                if a.meanSal < b.meanSal / 1.1 { a.removed = true } else if b.meanSal < a.meanSal / 1.1 { b.removed = true }
            }
        }
        for _ in 0..<2 {
            let trend = melodyTrend(contours)
            let left = contours.filter { !$0.removed }
            // Octave doubts: a clearly more voice-like line wins; otherwise the one nearer the melody.
            for a in left {
                for b in left where a !== b && !a.removed && !b.removed && overlaps(a, b) && abs(abs(a.meanPitch - b.meanPitch) - 12) <= 1.5 {
                    if a.vocal >= b.vocal + 0.8 {
                        b.removed = true
                    } else if b.vocal >= a.vocal + 0.8 {
                        a.removed = true
                    } else if distanceToTrend(a, trend) > distanceToTrend(b, trend) {
                        a.removed = true
                    } else {
                        b.removed = true
                    }
                }
            }
            for c in left where !c.removed && c.vocal < 1.5 && distanceToTrend(c, trend) > 8 { c.removed = true }
        }
        // A voice sings phrases: a lone note far from any other is a stray instrument.
        let isolation = Int(2500 / hopMs)
        let left = contours.filter { !$0.removed }.sorted { $0.start < $1.start }
        for (i, c) in left.enumerated() where c.vocal < 1.5 {
            let before = i > 0 ? c.start - left[i - 1].end : Int.max
            let after = i + 1 < left.count ? left[i + 1].start - c.end : Int.max
            if before > isolation && after > isolation { c.removed = true }
        }
    }

    /// Song-wide tuning offset in semitones (circular mean of the distance to the grid).
    private func tuningOffset(_ contours: [Contour]) -> Float {
        var cs = 0.0
        var sn = 0.0
        for c in contours {
            let w = Double(c.meanSal) * Double(c.pitch.count)
            let a = 2.0 * Double.pi * Double(gridDistance(c.meanPitch))
            cs += w * cos(a)
            sn += w * sin(a)
        }
        return (cs == 0 && sn == 0) ? 0 : Float(atan2(sn, cs) / (2.0 * Double.pi))
    }

    /// Signed distance to the nearest semitone, -0.5...0.5.
    private func gridDistance(_ midi: Float) -> Float { midi - Float(roundInt(midi)) }

    /// Pearson correlation of the pitch movements of two contours where they overlap.
    private func correlation(_ a: Contour, _ b: Contour) -> Float {
        var n = 0.0
        var sa = 0.0, sb = 0.0, saa = 0.0, sbb = 0.0, sab = 0.0
        for f in stride(from: max(a.start, b.start), through: min(a.end, b.end), by: 1) {
            let ia = f - a.start
            let ib = f - b.start
            guard ia >= 0, ia < a.dev.count, ib >= 0, ib < b.dev.count else { continue }
            let x = Double(a.dev[ia])
            let y = Double(b.dev[ib])
            if x.isNaN || y.isNaN { continue }
            n += 1
            sa += x; sb += y; saa += x * x; sbb += y * y; sab += x * y
        }
        if n < 5 { return 0 }
        let cov = sab - sa * sb / n
        let va = saa - sa * sa / n
        let vb = sbb - sb * sb / n
        return (va <= 1e-9 || vb <= 1e-9) ? 0 : Float(cov / (va * vb).squareRoot())
    }

    private func overlaps(_ a: Contour, _ b: Contour) -> Bool {
        let overlap = min(a.end, b.end) - max(a.start, b.start)
        return Float(overlap) >= 0.5 * Float(min(a.end - a.start, b.end - b.start))
    }

    /// Voice-weighted mean melody pitch, smoothed over ~4 s.
    private func melodyTrend(_ contours: [Contour]) -> [Float] {
        var sum = [Float](repeating: 0, count: frames)
        var weight = [Float](repeating: 0, count: frames)
        for c in contours where !c.removed {
            let w = c.meanSal * (1 + c.vocal) * (1 + c.vocal)
            for f in c.start...c.end {
                let p = c.pitchAt(f)
                if p.isNaN { continue }
                sum[f] += p * w
                weight[f] += w
            }
        }
        let raw = (0..<frames).map { weight[$0] > 0 ? sum[$0] / weight[$0] : Float.nan }
        let half = Int(2000 / hopMs)
        var out = [Float](repeating: 60, count: frames)
        var s = 0.0
        var n = 0
        var lo = 0
        var hi = -1
        var last: Float = 60
        for f in 0..<frames {
            while hi < min(frames - 1, f + half) {
                hi += 1
                if !raw[hi].isNaN { s += Double(raw[hi]); n += 1 }
            }
            while lo < f - half {
                if !raw[lo].isNaN { s -= Double(raw[lo]); n -= 1 }
                lo += 1
            }
            if n > 0 { last = Float(s / Double(n)) }
            out[f] = last
        }
        return out
    }

    private func distanceToTrend(_ c: Contour, _ trend: [Float]) -> Float {
        var s: Float = 0
        var n = 0
        for f in c.start...c.end {
            let p = c.pitchAt(f)
            if p.isNaN { continue }
            s += abs(p - trend[f])
            n += 1
        }
        return n == 0 ? 99 : s / Float(n)
    }
}
