import XCTest
import CantorialCore

/// Melody extraction on synthetic songs: a sung line (centre, vibrato, scoops) mixed with stereo
/// chords, bass, a plucked guitar in the same register and drums, optionally after an
/// instrumental intro where melodic instruments (violin with vibrato, piano, bent guitar) play.
/// Mirrors ExtractionTest of the Android app. The noise generator differs from java.util.Random,
/// so the thresholds follow a reference run of the Kotlin code with this same generator.
final class ExtractionTests: XCTestCase {
    private let rate: Float = 22050
    private let noteMs = 450
    private let restMs = 50
    private let melody = [64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62, 64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 62, 60, 60]
    private var voiceMs: Int { melody.count * (noteMs + restMs) }
    private var voiceStartMs = 1000
    private var totalMs = 0

    private func samples(_ ms: Int) -> Int { Int(Float(ms) * rate / 1000) }

    private func addTone(
        _ l: inout [Float], _ r: inout [Float], _ startMs: Int, _ durMs: Int, _ midi: Float, _ amp: Float,
        _ panL: Float, _ panR: Float, _ harmonics: Int, _ tilt: Double, decayMs: Float = 0, vibrato: Float = 0,
        drift: Int64? = nil, bendFrom: Float = 0, bendMs: Float = 0, vibratoHz: Double = 5.5
    ) {
        let start = samples(startMs)
        let n = samples(durMs)
        var rnd = drift.map { TestRandom($0) }
        var phase = 0.0
        var wander: Float = 0
        for i in 0..<n {
            let idx = start + i
            if idx >= l.count { break }
            let t = Float(i) / rate
            if rnd != nil && i % 64 == 0 {
                let g = Float(rnd!.nextGaussian())
                wander = min(max(0.995 * wander + 0.012 * g, -0.2), 0.2)
            }
            let bend: Float = bendMs > 0 && t * 1000 < bendMs ? bendFrom * (1 - t * 1000 / bendMs) : 0
            let wave = Float(sin(2.0 * Double.pi * vibratoHz * Double(t)))
            let vib: Float = vibrato * wave * min(1, t / 0.25) + wander + bend
            let hz = Pitch.midiToHz(midi + vib)
            phase += 2.0 * Double.pi * Double(hz) / Double(rate)
            var v = 0.0
            for h in 1...harmonics { v += sin(phase * Double(h)) / pow(Double(h), tilt) }
            var env = min(1, Float(i) / (0.02 * rate)) * min(1, Float(n - i) / (0.03 * rate))
            if decayMs > 0 { env *= exp(-t * 1000 / decayMs) }
            let s = Float(v * Double(amp) * Double(env))
            l[idx] += s * panL
            r[idx] += s * panR
        }
    }

    private func song(
        withVoice: Bool, withBand: Bool, seed: Int64 = 9, voiceAmp: Float = 0.10,
        mono: Bool = false, vibrato: Float = 0.3, introMs: Int = 0
    ) -> ([Float], [Float]) {
        voiceStartMs = 1000 + introMs
        totalMs = voiceStartMs + voiceMs + 1000
        let len = samples(totalMs)
        var l = [Float](repeating: 0, count: len)
        var r = [Float](repeating: 0, count: len)
        if withVoice {
            var intonation = TestRandom(seed * 31)
            for (i, m) in melody.enumerated() {
                let pitch = Float(m) + Float(intonation.nextGaussian() * 0.1)
                addTone(
                    &l, &r, voiceStartMs + i * (noteMs + restMs), noteMs, pitch, voiceAmp, 1, 1, 8, 0.9,
                    vibrato: vibrato, drift: vibrato == 0 ? seed + Int64(i) : nil, bendFrom: -0.3, bendMs: 70
                )
            }
        }
        if withBand {
            let chords = [[60, 64, 67], [65, 69, 72], [67, 71, 74], [60, 64, 67]]
            let bass = [36, 41, 43, 36]
            var t = 0
            var c = 0
            while t < totalMs {
                let chord = chords[c % chords.count]
                addTone(&l, &r, t, 2000, Float(chord[0]), 0.05, 1, 0.2, 10, 1.0)
                addTone(&l, &r, t, 2000, Float(chord[1]), 0.05, 0.2, 1, 10, 1.0)
                addTone(&l, &r, t, 2000, Float(chord[2]), 0.04, 0.6, 0.6, 10, 1.0)
                addTone(&l, &r, t, 2000, Float(bass[c % bass.count]), 0.16, 1, 1, 5, 1.0)
                for k in 0..<8 {
                    let note = chord[k % 3] + (k % 4 == 3 ? 12 : 0)
                    addTone(&l, &r, t + k * 250, 600, Float(note), 0.09, 0.9, 0.35, 6, 1.5, decayMs: 250)
                }
                t += 2000
                c += 1
            }
            if introMs > 0 {
                for (k, m) in [67, 69, 71, 72].enumerated() {
                    addTone(&l, &r, 1000 + k * 500, 480, Float(m), 0.10, 1, 0.35, 10, 1.0, vibrato: 0.25, vibratoHz: 6.0)
                }
                for (k, m) in [72, 71, 69, 67, 65, 64].enumerated() {
                    addTone(&l, &r, 3000 + k * 330, 320, Float(m), 0.14, 1, 1, 8, 1.3, decayMs: 350)
                }
                for (k, m) in [64, 62, 60].enumerated() {
                    addTone(&l, &r, 5000 + k * 650, 640, Float(m), 0.12, 0.4, 1, 7, 1.2,
                            decayMs: 700, vibrato: 0.15, bendFrom: -1, bendMs: 150)
                }
            }
            var rnd = TestRandom(seed)
            var d = 0
            while d < totalMs {
                let s = samples(d)
                for i in 0..<samples(60) {
                    if s + i >= len { break }
                    let v = Float(rnd.nextGaussian() * 0.08 * exp(-Double(i) / (0.015 * Double(rate))))
                    l[s + i] += v
                    r[s + i] += v
                }
                d += 500
            }
        }
        if mono {
            for i in l.indices {
                let m = (l[i] + r[i]) * 0.5
                l[i] = m
                r[i] = m
            }
        }
        return (l, r)
    }

    private func extract(_ l: [Float], _ r: [Float]) -> (MelodyExtractor.Result, [NoteEvent]) {
        let ex = MelodyExtractor(sampleRate: rate)
        for i in l.indices { ex.push(l[i], r[i]) }
        let res = ex.finish()
        return (res, Segmenter.segment(res.track, hopMs: res.hopMs, firstFrameMs: res.firstFrameMs, onsets: Segmenter.onsets(res.levels)))
    }

    /// Share of sung notes found with the right pitch at their centre.
    private func accuracy(_ notes: [NoteEvent]) -> Float {
        var ok = 0
        for (i, m) in melody.enumerated() {
            let centre = voiceStartMs + i * (noteMs + restMs) + noteMs / 2
            if notes.contains(where: { centre >= $0.startMs && centre <= $0.endMs && $0.midi == m }) { ok += 1 }
        }
        return Float(ok) / Float(melody.count)
    }

    func testFindsTheVoiceInsideAFullMix() {
        let (l, r) = song(withVoice: true, withBand: true)
        let notes = extract(l, r).1
        let acc = accuracy(notes)
        let old = TrackAnalyzer(sampleRate: rate, minClarity: 0.8, highPassHz: 110)
        for i in l.indices { old.push((l[i] + r[i]) * 0.5) }
        let oldNotes = Segmenter.segment(old.track(), hopMs: old.hopMs, firstFrameMs: old.firstFrameMs, onsets: Segmenter.onsets(old.levels()))
        let oldAcc = accuracy(oldNotes)
        print("Melody accuracy in a full mix: new \(acc), old \(oldAcc)")
        XCTAssertGreaterThanOrEqual(acc, 0.8)
        XCTAssertGreaterThan(acc, oldAcc + 0.2)
        let end = voiceStartMs + melody.count * (noteMs + restMs) + 200
        let outside = notes.filter { $0.endMs < voiceStartMs - 200 || $0.startMs > end }.count
        XCTAssertLessThanOrEqual(outside, 2)
    }

    func testMelodicInstrumentsAreNotTakenForVoice() {
        let (l, r) = song(withVoice: true, withBand: true, introMs: 6500)
        let notes = extract(l, r).1
        let acc = accuracy(notes)
        let inIntro = notes.filter { $0.endMs < voiceStartMs - 200 }
        print("With an instrumental intro: accuracy \(acc), intro notes \(inIntro.map(\.midi))")
        XCTAssertGreaterThanOrEqual(acc, 0.85)
        XCTAssertLessThanOrEqual(inIntro.count, 1)
    }

    func testInstrumentalWithMelodicInstrumentsHasAlmostNoMelody() {
        let (l, r) = song(withVoice: false, withBand: true, introMs: 6500)
        let (res, notes) = extract(l, r)
        print("Instrumental with lead instruments: voiced \(res.voicedRatio), \(notes.count) notes")
        XCTAssertLessThan(res.voicedRatio, 0.2)
        // Without any singer, a centred lead line with vibrato can still pass for a voice.
        XCTAssertLessThanOrEqual(notes.count, 6)
    }

    func testQuieterVoiceAndMonoMix() {
        let (l1, r1) = song(withVoice: true, withBand: true, voiceAmp: 0.06)
        let quiet = accuracy(extract(l1, r1).1)
        let (l2, r2) = song(withVoice: true, withBand: true, mono: true)
        let mono = accuracy(extract(l2, r2).1)
        print("Quieter voice: \(quiet), mono mix: \(mono)")
        XCTAssertGreaterThanOrEqual(quiet, 0.6)
        XCTAssertGreaterThanOrEqual(mono, 0.7)
    }

    func testStraightVoiceWithoutVibrato() {
        let (l, r) = song(withVoice: true, withBand: true, vibrato: 0)
        let acc = accuracy(extract(l, r).1)
        print("Voice without vibrato: \(acc)")
        XCTAssertGreaterThanOrEqual(acc, 0.5)
    }

    func testACappellaVoiceIsTranscribed() {
        let (l, r) = song(withVoice: true, withBand: false)
        XCTAssertGreaterThanOrEqual(accuracy(extract(l, r).1), 0.9)
    }

    func testInstrumentalOnlyHasAlmostNoMelody() {
        let (l, r) = song(withVoice: false, withBand: true)
        let res = extract(l, r).0
        print("Instrumental only: voiced \(res.voicedRatio)")
        XCTAssertLessThan(res.voicedRatio, 0.3)
    }

    func testExtractionIsFast() {
        let (l, r) = song(withVoice: true, withBand: true)
        let t0 = Date()
        _ = extract(l, r)
        let seconds = Double(l.count) / Double(rate)
        let elapsed = Date().timeIntervalSince(t0)
        print("Extraction: \(elapsed) s for \(seconds) s of audio")
        XCTAssertLessThan(elapsed, seconds / 2)
    }
}
