import XCTest
import CantorialCore

final class ChordsTests: XCTestCase {
    func testRecognisesChordSymbols() {
        for c in ["C", "Am", "F#m7", "Bb", "G7", "D/F#", "C7M", "E7(#9)", "F#m7(b5)", "Asus4", "Cadd9", "Bº", "G°", "D7/9", "A7+", "C6/9", "Ebmaj7", "D7/9/F#", "E4", "Gm6"] {
            XCTAssertTrue(Chords.isChord(c), "\(c) should be a chord")
        }
        for w in ["Amor", "Deus", "a", "e", "Casa", "Fé", "Bem", "Gente", "Do", "H7", "A)", "Cm(", ""] {
            XCTAssertFalse(Chords.isChord(w), "\(w) should not be a chord")
        }
    }

    func testTransposesSingleChords() {
        XCTAssertEqual(Chords.transposeChord("C", 2, flats: false), "D")
        XCTAssertEqual(Chords.transposeChord("Am", 2, flats: false), "Bm")
        XCTAssertEqual(Chords.transposeChord("F#m7", 2, flats: false), "G#m7")
        XCTAssertEqual(Chords.transposeChord("F#m7", 2, flats: true), "Abm7")
        XCTAssertEqual(Chords.transposeChord("D/F#", 2, flats: false), "E/G#")
        XCTAssertEqual(Chords.transposeChord("C7M(9)", -2, flats: true), "Bb7M(9)")
        XCTAssertEqual(Chords.transposeChord("D7/9/F#", 2, flats: false), "E7/9/G#")
        XCTAssertEqual(Chords.transposeChord("B", 1, flats: false), "C")
        XCTAssertEqual(Chords.transposeChord("C", -1, flats: false), "B")
        XCTAssertEqual(Chords.transposeChord("palavra", 3, flats: false), "palavra")
    }

    func testTellsChordLinesFromLyrics() {
        XCTAssertEqual(Chords.chordSpans("C        G/B     Am7").count, 3)
        XCTAssertEqual(Chords.chordSpans("Intro: C  G  Am  F").count, 4)
        XCTAssertEqual(Chords.chordSpans("(C G Am F) 2x").count, 4)
        XCTAssertEqual(Chords.chordSpans("| D | A7 | % |").count, 2)
        XCTAssertEqual(Chords.chordSpans("Tom: G").count, 1)
        XCTAssertTrue(Chords.chordSpans("Em Deus eu confio").isEmpty)
        XCTAssertTrue(Chords.chordSpans("A casa caiu").isEmpty)
        XCTAssertTrue(Chords.chordSpans("E|---0---2---3---|").isEmpty)
        XCTAssertTrue(Chords.chordSpans("Refrão:").isEmpty)
        XCTAssertTrue(Chords.chordSpans("").isEmpty)
        XCTAssertEqual(Chords.spans("[C]Parabéns pra vo[G7]cê").count, 2)
        XCTAssertTrue(Chords.spans("[Refrão] cantar de novo").isEmpty)
    }

    func testKeepsChordsAboveTheSameSyllables() {
        let line = "C       G       Am      F"
        let up = Chords.transposeLine(line, 1, flats: false)
        XCTAssertEqual(up, "C#      G#      A#m     F#")
        XCTAssertEqual(Chords.transposeLine(up, -1, flats: false), line)
        XCTAssertEqual(Chords.transposeLine("Bb  Eb", -1, flats: true), "A   D")
        XCTAssertEqual(Chords.transposeLine("C D E", 1, flats: false), "C# D# F")
    }

    func testTransposesAWholeSheetAndPicksTheSpelling() {
        let sheet = [
            "Tom: C",
            "Intro: C  G/B  Am  F",
            "",
            "C           G/B",
            "Parabéns pra você",
            "    Am          F",
            "Nesta data querida",
            "[Dm]Muitas felici[G7]dades",
        ].joined(separator: "\n")
        let f = Chords.transpose(sheet, 5).components(separatedBy: "\n")
        XCTAssertEqual(f[0], "Tom: F")
        XCTAssertEqual(f[1], "Intro: F  C/E  Dm  Bb")
        XCTAssertEqual(f[3], "F           C/E")
        XCTAssertEqual(f[4], "Parabéns pra você")
        XCTAssertEqual(f[5], "    Dm          Bb")
        XCTAssertEqual(f[7], "[Gm]Muitas felici[C7]dades")
        XCTAssertEqual(Chords.transpose(sheet, 4).components(separatedBy: "\n")[1], "Intro: E  B/D# C#m A")
        XCTAssertEqual(Chords.transpose(sheet, 0), sheet)
        XCTAssertEqual(Chords.transpose(sheet, 12), sheet)
        XCTAssertEqual(Chords.transpose(Chords.transpose(sheet, 3), -3), sheet)
    }

    func testNamesTheKeyFromTheFirstChord() {
        XCTAssertEqual(Chords.keyOf("G  D  Em  C\nletra").map(Chords.keyName), "G")
        XCTAssertEqual(Chords.keyOf("letra sem acorde\nF#m7  B7").map(Chords.keyName), "F#m")
        XCTAssertEqual(Chords.keyOf("G  D  Em  C", 3).map(Chords.keyName), "Bb")
        XCTAssertEqual(Chords.keyOf("Em  C", 3).map(Chords.keyName), "Gm")
        XCTAssertNil(Chords.keyOf("só letra, sem acordes"))
        XCTAssertEqual(Chords.firstChord("Tom: C\nC G"), "C")
    }
}
