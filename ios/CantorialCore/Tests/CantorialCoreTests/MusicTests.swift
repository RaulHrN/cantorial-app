import XCTest
import CantorialCore

final class MusicTests: XCTestCase {
    func testMidiAndFrequencyRoundTrip() {
        XCTAssertEqual(Pitch.hzToMidi(440), 69, accuracy: 1e-4)
        XCTAssertEqual(Pitch.hzToMidi(261.6256), 60, accuracy: 1e-3)
        XCTAssertEqual(Pitch.midiToHz(69), 440, accuracy: 1e-3)
        XCTAssertEqual(Pitch.hzToMidi(432, a4: 432), 69, accuracy: 1e-4)
    }

    func testFoldedCentsForgivesOctaves() {
        XCTAssertEqual(Pitch.foldedCents(72, 60), 0, accuracy: 1e-3)
        XCTAssertEqual(Pitch.foldedCents(48.2, 60), 20, accuracy: 1e-2)
        XCTAssertEqual(Pitch.foldedCents(59.7, 60), -30, accuracy: 1e-2)
    }

    func testNoteNames() {
        XCTAssertEqual(NoteNames.full(69, .solfege), "Lá4")
        XCTAssertEqual(NoteNames.full(60, .letters), "C4")
        XCTAssertEqual(NoteNames.pitchClass(10, .solfege, flats: true), "Sib")
        XCTAssertEqual(NoteNames.full(54, .letters), "F#3")
        XCTAssertEqual(NoteNames.octave(0), -1)
    }

    func testKeyDetection() {
        let melody = [67, 67, 69, 67, 72, 71, 67, 67, 69, 67, 74, 72, 67, 67, 79, 76, 72, 71, 69, 77, 77, 76, 72, 74, 72]
        let notes = melody.enumerated().map { NoteEvent($0.offset * 400, 380, $0.element) }
        XCTAssertEqual(KeyDetector.detect(notes), Key(0, false))

        let minor = [57, 59, 60, 62, 64, 65, 67, 69, 67, 65, 64, 62, 60, 59, 57]
        let minorNotes = minor.enumerated().map { NoteEvent($0.offset * 400, $0.element == 57 ? 1500 : 380, $0.element) }
        XCTAssertEqual(KeyDetector.detect(minorNotes), Key(9, true))
    }

    func testDiatonicThirdsInMajor() {
        let c = Key(0, false)
        let melody = [60, 62, 64, 65, 67, 69, 71, 72]
        XCTAssertEqual(melody.map { Harmony.note($0, key: c, steps: 2) }, [64, 65, 67, 69, 71, 72, 74, 76])
        XCTAssertEqual(melody.map { Harmony.note($0, key: c, steps: -2) }, [57, 59, 60, 62, 64, 65, 67, 69])
    }

    func testChromaticNotesGetMusicalThirds() {
        let c = Key(0, false)
        XCTAssertEqual(Harmony.note(66, key: c, steps: 2), 69)
        XCTAssertEqual(Harmony.note(70, key: c, steps: 2), 74)
        XCTAssertEqual(Harmony.note(63, key: c, steps: 2), 67)
        let am = Key(9, true)
        XCTAssertEqual(Harmony.note(68, key: am, steps: 2), 71)
        XCTAssertEqual(Harmony.note(68, key: am, steps: -2), 64)
    }

    func testHarmonyModesShiftOctaves() {
        let g = Key(7, false)
        let melody = [NoteEvent(0, 500, 67), NoteEvent(500, 500, 71)]
        XCTAssertEqual(Harmony.voice(melody, key: g, mode: .sixthBelow).map(\.midi), [59, 62])
        XCTAssertEqual(Harmony.voice(melody, key: g, mode: .sixthAbove).map(\.midi), [76, 79])
    }

    func testVoiceTypes() {
        XCTAssertEqual(VoiceType.classify(45, 68), .baritone)
        XCTAssertEqual(VoiceType.classify(60, 86), .soprano)
        XCTAssertEqual(VoiceType.classify(48, 72), .tenor)
        XCTAssertEqual(VoiceType.classify(57, 80), .mezzo)
    }

    func testNotationParsing() {
        let r = Notation.parse("Dó Ré Mi:2 - Fá#4 sol/0.5 C5 Bb4 si", bpm: 120)
        XCTAssertNil(r.error)
        XCTAssertEqual(r.notes.map(\.midi), [60, 62, 64, 66, 67, 72, 70, 71])
        XCTAssertEqual(r.notes[0].startMs, 0)
        XCTAssertEqual(r.notes[1].startMs, 500)
        XCTAssertEqual(r.notes[2].startMs, 1000)
        XCTAssertEqual(r.notes[3].startMs, 3000)
        XCTAssertNotNil(Notation.parse("xyz", bpm: 100).error)
        XCTAssertNotNil(Notation.parse("", bpm: 100).error)
    }

    func testNotationPicksClosestOctave() {
        XCTAssertEqual(Notation.parse("Si4 Dó Ré", bpm: 100).notes.map(\.midi), [71, 72, 74])
        XCTAssertEqual(Notation.parse("Dó5 Si Lá", bpm: 100).notes.map(\.midi), [72, 71, 69])
    }

    func testPhrasesSplitAtRests() {
        let notes = [
            NoteEvent(0, 400, 60), NoteEvent(400, 400, 62), NoteEvent(800, 400, 64),
            NoteEvent(2500, 400, 65), NoteEvent(2900, 400, 67),
        ]
        let p = Phrases.split(notes)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual([p[0].startMs, p[0].endMs], [0, 1200])
        XCTAssertEqual([p[1].startMs, p[1].endMs], [2500, 3300])
    }

    func testSegmenterFindsNotesInNoisyTrack() {
        let hop: Float = 23.2
        var rnd = TestRandom(3)
        var track: [Float] = []
        let melody = [60, 62, 64, 64, 67]
        for m in melody {
            for _ in 0..<17 { track.append(Float(m) + 0.2 + Float(rnd.nextGaussian() * 0.12)) }
            for _ in 0..<4 { track.append(.nan) }
        }
        track[4 * 21] = 66
        track[2 * 21 + 8] = 76
        let notes = Segmenter.segment(track, hopMs: hop)
        XCTAssertEqual(notes.map(\.midi), melody)
        for (i, n) in notes.enumerated() {
            XCTAssertEqual(Float(n.startMs), Float(i * 21) * hop, accuracy: 3 * hop)
            XCTAssertTrue((300...450).contains(n.durMs), "duration \(n.durMs)")
        }
    }

    func testSegmenterSplitsLegatoSteps() {
        let hop: Float = 23.2
        var track: [Float] = []
        for m in [67, 69, 71, 72] { for _ in 0..<15 { track.append(Float(m)) } }
        let notes = Segmenter.segment(track, hopMs: hop)
        XCTAssertEqual(notes.map(\.midi), [67, 69, 71, 72])
        XCTAssertLessThanOrEqual(abs(Int((15 * hop).rounded()) - notes[1].startMs), 2 * Int(hop.rounded()))
    }
}
