import XCTest
import CantorialCore

final class PitchDetectorTests: XCTestCase {
    private let rate: Float = 22050
    private let window = 1024

    private func tone(_ hz: Float, _ harmonics: [Float] = [1], noise: Float = 0, seed: Int64 = 1) -> [Float] {
        var rnd = TestRandom(seed)
        return (0..<window).map { i in
            var v = 0.0
            for h in harmonics.indices {
                v += Double(harmonics[h]) * sin(2.0 * Double.pi * Double(hz) * Double(h + 1) * Double(i) / Double(rate) + Double(h))
            }
            return Float(0.3 * v + Double(noise) * rnd.nextGaussian())
        }
    }

    private func centsError(_ expected: Float, _ actual: Float) -> Float {
        abs(Pitch.hzToMidi(actual) - Pitch.hzToMidi(expected)) * 100
    }

    func testDetectsPureTonesAcrossVocalRange() {
        let detector = PitchDetector(sampleRate: rate, windowSize: window)
        for hz: Float in [70, 82.4, 110, 196, 261.6, 440, 523.3, 880, 1046.5, 1318.5] {
            let f = detector.detect(tone(hz))
            XCTAssertGreaterThan(f, 0, "no pitch for \(hz)")
            XCTAssertLessThan(centsError(hz, f), 5, "\(hz) detected as \(f)")
            XCTAssertGreaterThan(detector.clarity, 0.9, "clarity for \(hz)")
        }
    }

    func testVoiceLikeSpectrumHasNoOctaveErrors() {
        let detector = PitchDetector(sampleRate: rate, windowSize: window)
        let spectrum: [Float] = [0.4, 1, 0.7, 0.5, 0.3, 0.2, 0.1]
        for hz: Float in [98, 147, 220, 330, 494, 660] {
            let f = detector.detect(tone(hz, spectrum))
            XCTAssertLessThan(centsError(hz, f), 10, "\(hz) detected as \(f)")
        }
    }

    func testMissingFundamentalStillGivesPitch() {
        let detector = PitchDetector(sampleRate: rate, windowSize: window)
        let f = detector.detect(tone(150, [0, 1, 0.8, 0.6]))
        XCTAssertLessThan(centsError(150, f), 10, "detected \(f)")
    }

    func testNoisyToneIsStillDetected() {
        let detector = PitchDetector(sampleRate: rate, windowSize: window)
        let f = detector.detect(tone(311, [1, 0.5, 0.3], noise: 0.05))
        XCTAssertLessThan(centsError(311, f), 10, "detected \(f)")
    }

    func testWhiteNoiseHasLowClarity() {
        let detector = PitchDetector(sampleRate: rate, windowSize: window)
        var rnd = TestRandom(7)
        let noise = (0..<window).map { _ in Float(0.2 * rnd.nextGaussian()) }
        _ = detector.detect(noise)
        XCTAssertLessThan(detector.clarity, 0.6)
    }

    func testSilenceReturnsNoPitch() {
        let detector = PitchDetector(sampleRate: rate, windowSize: window)
        XCTAssertEqual(detector.detect([Float](repeating: 0, count: window)), -1)
    }

    func testHighPassKeepsVoiceAndRemovesRumble() {
        var hp = Biquad.highPass(sampleRate: rate, cutoff: 70)
        var maxLow: Float = 0
        for i in 0..<8000 {
            let y = hp.process(Float(0.5 * sin(2.0 * Double.pi * 15.0 * Double(i) / Double(rate))))
            if i > 4000 { maxLow = max(maxLow, abs(y)) }
        }
        XCTAssertLessThan(maxLow, 0.03)
        hp.reset()
        var maxHigh: Float = 0
        for i in 0..<8000 {
            let y = hp.process(Float(0.5 * sin(2.0 * Double.pi * 300.0 * Double(i) / Double(rate))))
            if i > 4000 { maxHigh = max(maxHigh, abs(y)) }
        }
        XCTAssertGreaterThan(maxHigh, 0.45)
    }

    func testSmootherRemovesSingleOctaveJump() {
        var s = PitchSmoother()
        _ = s.push(60)
        _ = s.push(60.1)
        XCTAssertEqual(s.push(72), 60.1, accuracy: 0.001)
        XCTAssertEqual(s.push(60.2), 60.2, accuracy: 0.001)
    }

    /// A "sung" melody: harmonics, 5.5 Hz vibrato, onset glides, breath noise and rests.
    private func sing(_ melody: [Int], noteMs: Int, restMs: Int, seed: Int64 = 11) -> [Float] {
        var rnd = TestRandom(seed)
        let noteSamples = Int(Float(noteMs) * rate / 1000)
        let restSamples = Int(Float(restMs) * rate / 1000)
        var out = [Float](repeating: 0, count: melody.count * (noteSamples + restSamples) + restSamples)
        let harmonics: [Double] = [0.6, 1, 0.6, 0.4, 0.25, 0.15]
        var pos = restSamples
        var prev = Float(melody[0])
        for m in melody {
            var phase = 0.0
            for i in 0..<noteSamples {
                let t = Float(i) / rate
                let glide: Float = t < 0.06 ? (prev - Float(m)) * (1 - t / 0.06) : 0
                let vibrato = 0.3 * Float(sin(2.0 * Double.pi * 5.5 * Double(t))) * min(1, t / 0.3)
                let hz = Pitch.midiToHz(Float(m) + glide + vibrato)
                phase += 2.0 * Double.pi * Double(hz) / Double(rate)
                var v = 0.0
                for h in harmonics.indices { v += harmonics[h] * sin(phase * Double(h + 1)) }
                let env = min(1, Float(i) / 400) * min(1, Float(noteSamples - i) / 600)
                out[pos + i] = Float(0.15 * v * Double(env) + 0.01 * rnd.nextGaussian())
            }
            prev = Float(m)
            pos += noteSamples + restSamples
        }
        for i in out.indices where out[i] == 0 { out[i] = Float(0.003 * rnd.nextGaussian()) }
        return out
    }

    private func transcribe(_ audio: [Float]) -> [NoteEvent] {
        let analyzer = TrackAnalyzer(sampleRate: rate)
        for s in audio { analyzer.push(s) }
        return Segmenter.segment(analyzer.track(), hopMs: analyzer.hopMs, firstFrameMs: analyzer.firstFrameMs, onsets: Segmenter.onsets(analyzer.levels()))
    }

    func testSungMelodyIsTranscribed() {
        // "Brilha, brilha, estrelinha" in G major.
        let melody = [55, 55, 62, 62, 64, 64, 62, 60, 60, 59, 59, 57, 57, 55]
        let notes = transcribe(sing(melody, noteMs: 420, restMs: 80))
        XCTAssertEqual(notes.map(\.midi), melody)
        for (i, n) in notes.enumerated() {
            let expected = 80 + i * 500
            XCTAssertLessThan(abs(n.startMs - expected), 80, "note \(i) starts at \(n.startMs)")
        }
        XCTAssertEqual(KeyDetector.detect(notes), Key(7, false))
        let second = Harmony.voice(notes, key: Key(7, false), mode: .thirdAbove).map(\.midi)
        XCTAssertEqual(second, [59, 59, 66, 66, 67, 67, 66, 64, 64, 62, 62, 60, 60, 59])
    }

    func testLegatoMelodyWithoutRests() {
        let melody = [60, 62, 64, 65, 67, 65, 64, 62, 60]
        XCTAssertEqual(transcribe(sing(melody, noteMs: 350, restMs: 0)).map(\.midi), melody)
    }
}
