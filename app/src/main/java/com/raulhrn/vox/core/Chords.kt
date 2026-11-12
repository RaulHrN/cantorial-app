package com.raulhrn.vox.core

/** A chord sheet (cifra): lyrics with chord symbols above the words or inline in brackets. */
data class Cifra(
    val id: String,
    val title: String,
    val artist: String,
    val text: String,
    /** Semitones the sheet is shown above (+) or below (-) the key it was written in. */
    val transpose: Int = 0,
    val createdAt: Long = 0L,
)

/** An ordered list of chord sheets for a performance. */
data class Setlist(
    val id: String,
    val name: String,
    val items: List<String>,
    val createdAt: Long = 0L,
)

/**
 * Reads and transposes chord symbols in chord sheets.
 *
 * A chord is a root (A-G with # or b), a quality made of the usual pieces (m, maj, 7, 7M, sus4,
 * dim, º, +, (b5), /9 ...) and an optional bass note after a slash. Two layouts are understood:
 * lines made only of chords, written above the lyrics, and chords inside square brackets in the
 * middle of the lyrics ("[C]Parabéns pra vo[G]cê").
 */
object Chords {
    private val SHARP = arrayOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
    private val FLAT = arrayOf("C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B")
    private val NATURAL = intArrayOf(9, 11, 0, 2, 4, 5, 7) // A B C D E F G

    private const val QUALITY = "(?:maj|min|dim|aug|sus|add|m|M|º|°|\\+|-|[0-9]|#|b|\\(|\\)|,|/(?=[0-9]))*"
    private val CHORD = Regex("^([A-G])([#b♯♭]?)($QUALITY)(?:/([A-G])([#b♯♭]?))?$")
    private val BRACKET = Regex("\\[([^\\[\\]]+)]")
    private val TOKEN = Regex("\\S+")
    private val LABEL = Regex("^\\s*[^\\s:]{1,24}(?: [^\\s:]{1,12})?:")

    /** Things that may sit between chords in a chord line without being chords. */
    private val FILLER = Regex("^(?:[|/\\\\\\-–—.%*]+|\\(?[xX]?[0-9]{1,2}[xX]?\\)?|N\\.?C\\.?|\\(|\\))$")

    class Parsed(val root: Int, val quality: String, val bass: Int)

    private fun pitchClass(letter: String, accidental: String): Int {
        val base = NATURAL[letter[0] - 'A']
        return Math.floorMod(
            base + when (accidental) {
                "#", "♯" -> 1
                "b", "♭" -> -1
                else -> 0
            },
            12,
        )
    }

    /** The parts of a chord symbol, or null when [token] is not a chord. [Parsed.bass] is -1 without a bass note. */
    fun parse(token: String): Parsed? {
        val m = CHORD.matchEntire(token) ?: return null
        val quality = m.groupValues[3]
        // Unbalanced parentheses mean ordinary text, e.g. "A)" in a list.
        if (quality.count { it == '(' } != quality.count { it == ')' }) return null
        val bass = if (m.groupValues[4].isEmpty()) -1 else pitchClass(m.groupValues[4], m.groupValues[5])
        return Parsed(pitchClass(m.groupValues[1], m.groupValues[2]), quality, bass)
    }

    fun isChord(token: String): Boolean = parse(token) != null

    private fun isMinor(quality: String): Boolean =
        (quality.startsWith("m") && !quality.startsWith("maj")) || quality.startsWith("min")

    /** [chord] moved by [semitones], spelled with flats or sharps. Text that is not a chord comes back unchanged. */
    fun transposeChord(chord: String, semitones: Int, flats: Boolean): String {
        val p = parse(chord) ?: return chord
        val names = if (flats) FLAT else SHARP
        val out = StringBuilder(names[Math.floorMod(p.root + semitones, 12)]).append(p.quality)
        if (p.bass >= 0) out.append('/').append(names[Math.floorMod(p.bass + semitones, 12)])
        return out.toString()
    }

    /** Position of the text after a leading label such as "Intro:" or "Refrão:" (0 when there is none). */
    private fun afterLabel(line: String): Int = LABEL.find(line)?.range?.last?.plus(1) ?: 0

    /** Ranges of the chord symbols of a line made only of chords; empty for lyrics and other text. */
    fun chordSpans(line: String): List<IntRange> {
        val start = afterLabel(line)
        val spans = ArrayList<IntRange>()
        for (m in TOKEN.findAll(line, start)) {
            var from = m.range.first
            var to = m.range.last
            // Parentheses around a group of chords: "(C G Am F) 2x".
            if (line[from] == '(' && !balanced(line, from, to)) from++
            if (to >= from && line[to] == ')' && !balanced(line, from, to)) to--
            if (to < from) continue
            val token = line.substring(from, to + 1)
            when {
                isChord(token) -> spans.add(from..to)
                FILLER.matches(token) -> Unit
                // A bracketed chord or section name: "[C]" counts, "[Refrão]" is ignored.
                token.startsWith("[") && token.endsWith("]") -> {
                    if (isChord(token.substring(1, token.length - 1))) spans.add(from + 1..to - 1)
                }
                else -> return emptyList()
            }
        }
        return spans
    }

    private fun balanced(line: String, from: Int, to: Int): Boolean {
        var depth = 0
        for (i in from..to) {
            if (line[i] == '(') depth++ else if (line[i] == ')') depth--
        }
        return depth == 0
    }

    /** Ranges of chords written inside square brackets in a lyrics line. */
    fun inlineSpans(line: String): List<IntRange> =
        BRACKET.findAll(line).filter { isChord(it.groupValues[1]) }.map { it.range.first + 1..it.range.last - 1 }.toList()

    /** Every chord range of a line, whichever layout it uses. */
    fun spans(line: String): List<IntRange> = chordSpans(line).ifEmpty { inlineSpans(line) }

    /**
     * Transposes one line. In chord lines the spacing after each chord grows or shrinks so the
     * following chords stay above the same syllables.
     */
    fun transposeLine(line: String, semitones: Int, flats: Boolean): String {
        val spans = spans(line)
        if (spans.isEmpty()) return line
        val aligned = chordSpans(line).isNotEmpty()
        val out = StringBuilder()
        var pos = 0
        var debt = 0 // columns the output is ahead (+) of the original
        for (span in spans) {
            var gap = line.substring(pos, span.first)
            if (aligned && debt != 0 && gap.isNotEmpty() && gap.isBlank()) {
                if (debt > 0) {
                    val cut = minOf(debt, gap.length - 1)
                    gap = gap.substring(cut)
                    debt -= cut
                } else {
                    gap += " ".repeat(-debt)
                    debt = 0
                }
            }
            out.append(gap)
            val old = line.substring(span.first, span.last + 1)
            val new = transposeChord(old, semitones, flats)
            out.append(new)
            debt += new.length - old.length
            pos = span.last + 1
        }
        out.append(line.substring(pos))
        return out.toString()
    }

    /** The first chord of the sheet, which by convention names its key. */
    fun firstChord(text: String): String? {
        for (line in text.lineSequence()) {
            val span = spans(line).firstOrNull() ?: continue
            return line.substring(span.first, span.last + 1)
        }
        return null
    }

    /** Key of the sheet after moving it by [semitones], guessed from its first chord. */
    fun keyOf(text: String, semitones: Int = 0): Key? {
        val p = parse(firstChord(text) ?: return null) ?: return null
        return Key(Math.floorMod(p.root + semitones, 12), isMinor(p.quality))
    }

    /** Name of a key the way chord sheets write it: "G", "F#m", "Bb". */
    fun keyName(key: Key): String = (if (key.prefersFlats) FLAT else SHARP)[key.tonic] + if (key.minor) "m" else ""

    /** The whole sheet moved by [semitones]; flats or sharps follow the resulting key. */
    fun transpose(text: String, semitones: Int): String {
        val steps = Math.floorMod(semitones, 12)
        if (steps == 0) return text
        val flats = keyOf(text, steps)?.prefersFlats ?: false
        return text.lineSequence().joinToString("\n") { transposeLine(it, steps, flats) }
    }
}
