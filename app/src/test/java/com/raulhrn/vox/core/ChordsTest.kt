package com.raulhrn.vox.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChordsTest {
    @Test
    fun recognisesChordSymbols() {
        for (c in listOf("C", "Am", "F#m7", "Bb", "G7", "D/F#", "C7M", "E7(#9)", "F#m7(b5)", "Asus4", "Cadd9", "Bº", "G°", "D7/9", "A7+", "C6/9", "Ebmaj7", "D7/9/F#", "E4", "Gm6")) {
            assertTrue("$c should be a chord", Chords.isChord(c))
        }
        for (w in listOf("Amor", "Deus", "a", "e", "Casa", "Fé", "Bem", "Gente", "Do", "H7", "A)", "Cm(", "")) {
            assertFalse("$w should not be a chord", Chords.isChord(w))
        }
    }

    @Test
    fun transposesSingleChords() {
        assertEquals("D", Chords.transposeChord("C", 2, false))
        assertEquals("Bm", Chords.transposeChord("Am", 2, false))
        assertEquals("G#m7", Chords.transposeChord("F#m7", 2, false))
        assertEquals("Abm7", Chords.transposeChord("F#m7", 2, true))
        assertEquals("E/G#", Chords.transposeChord("D/F#", 2, false))
        assertEquals("Bb7M(9)", Chords.transposeChord("C7M(9)", -2, true))
        assertEquals("A#7M(9)", Chords.transposeChord("C7M(9)", -2, false))
        assertEquals("E7/9/G#", Chords.transposeChord("D7/9/F#", 2, false))
        assertEquals("C", Chords.transposeChord("B", 1, false))
        assertEquals("B", Chords.transposeChord("C", -1, false))
        assertEquals("C", Chords.transposeChord("C", 12, false))
        assertEquals("palavra", Chords.transposeChord("palavra", 3, false))
    }

    @Test
    fun tellsChordLinesFromLyrics() {
        assertEquals(3, Chords.chordSpans("C        G/B     Am7").size)
        assertEquals(4, Chords.chordSpans("Intro: C  G  Am  F").size)
        assertEquals(4, Chords.chordSpans("(C G Am F) 2x").size)
        assertEquals(2, Chords.chordSpans("| D | A7 | % |").size)
        assertEquals(1, Chords.chordSpans("Tom: G").size)
        assertTrue(Chords.chordSpans("Em Deus eu confio").isEmpty())
        assertTrue(Chords.chordSpans("A casa caiu").isEmpty())
        assertTrue(Chords.chordSpans("E|---0---2---3---|").isEmpty())
        assertTrue(Chords.chordSpans("Refrão:").isEmpty())
        assertTrue(Chords.chordSpans("").isEmpty())
        assertEquals(2, Chords.spans("[C]Parabéns pra vo[G7]cê").size)
        assertTrue(Chords.spans("[Refrão] cantar de novo").isEmpty())
    }

    @Test
    fun keepsChordsAboveTheSameSyllables() {
        val line = "C       G       Am      F"
        val up = Chords.transposeLine(line, 1, false)
        assertEquals("C#      G#      A#m     F#", up)
        // Back down: the same columns again.
        assertEquals(line, Chords.transposeLine(up, -1, false))
        // A shorter chord gets the missing space back.
        assertEquals("A   D", Chords.transposeLine("Bb  Eb", -1, true))
        // Chords one space apart never glue together.
        assertEquals("C# D# F", Chords.transposeLine("C D E", 1, false))
    }

    @Test
    fun transposesAWholeSheetAndPicksTheSpelling() {
        val sheet = """
            Tom: C
            Intro: C  G/B  Am  F

            C           G/B
            Parabéns pra você
                Am          F
            Nesta data querida
            [Dm]Muitas felici[G7]dades
        """.trimIndent()
        val f = Chords.transpose(sheet, 5)
        assertEquals("Tom: F", f.lines()[0])
        assertEquals("Intro: F  C/E  Dm  Bb", f.lines()[1])
        assertEquals("F           C/E", f.lines()[3])
        assertEquals("Parabéns pra você", f.lines()[4])
        assertEquals("    Dm          Bb", f.lines()[5])
        assertEquals("[Gm]Muitas felici[C7]dades", f.lines()[7])
        // A sharp key spells with sharps; longer names take up the spaces that follow them.
        assertEquals("Intro: E  B/D# C#m A", Chords.transpose(sheet, 4).lines()[1])
        // No change and a full octave leave the text alone.
        assertEquals(sheet, Chords.transpose(sheet, 0))
        assertEquals(sheet, Chords.transpose(sheet, 12))
        // Up and back down gives the original.
        assertEquals(sheet, Chords.transpose(Chords.transpose(sheet, 3), -3))
    }

    @Test
    fun namesTheKeyFromTheFirstChord() {
        assertEquals("G", Chords.keyName(Chords.keyOf("G  D  Em  C\nletra")!!))
        assertEquals("F#m", Chords.keyName(Chords.keyOf("letra sem acorde\nF#m7  B7")!!))
        assertEquals("Bb", Chords.keyName(Chords.keyOf("G  D  Em  C", 3)!!))
        assertEquals("Gm", Chords.keyName(Chords.keyOf("Em  C", 3)!!))
        assertNull(Chords.keyOf("só letra, sem acordes"))
        assertEquals("C", Chords.firstChord("Tom: C\nC G"))
    }
}
