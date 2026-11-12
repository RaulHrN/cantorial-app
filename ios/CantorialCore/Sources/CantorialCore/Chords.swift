import Foundation

/// A chord sheet (cifra): lyrics with chord symbols above the words or inline in brackets.
public struct Cifra: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var artist: String
    public var text: String
    /// Semitones the sheet is shown above (+) or below (-) the key it was written in.
    public var transpose: Int
    public var createdAt: Date

    public init(id: String, title: String, artist: String, text: String, transpose: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.artist = artist
        self.text = text
        self.transpose = transpose
        self.createdAt = createdAt
    }
}

/// An ordered list of chord sheets for a performance.
public struct Setlist: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var items: [String]
    public var createdAt: Date

    public init(id: String, name: String, items: [String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
    }
}

/// Reads and transposes chord symbols in chord sheets. Mirrors Chords of the Android app.
///
/// A chord is a root (A-G with # or b), a quality made of the usual pieces (m, maj, 7, 7M, sus4,
/// dim, º, +, (b5), /9 ...) and an optional bass note after a slash. Two layouts are understood:
/// lines made only of chords, written above the lyrics, and chords inside square brackets in the
/// middle of the lyrics ("[C]Parabéns pra vo[G]cê"). Positions are character offsets in the line.
public enum Chords {
    private static let sharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flat = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let natural: [Character: Int] = ["A": 9, "B": 11, "C": 0, "D": 2, "E": 4, "F": 5, "G": 7]
    private static let qualityWords = ["maj", "min", "dim", "aug", "sus", "add", "m", "M", "º", "°", "+", "-", "#", "b", "(", ")", ","]

    public struct Parsed {
        public let root: Int
        public let quality: String
        /// -1 without a bass note.
        public let bass: Int
    }

    private static func accidental(_ c: Character) -> Int? {
        switch c {
        case "#", "♯": return 1
        case "b", "♭": return -1
        default: return nil
        }
    }

    /// Reads a note name at `i`, returning its pitch class and the position after it.
    private static func note(_ s: [Character], _ i: Int) -> (pc: Int, next: Int)? {
        guard i < s.count, let base = natural[s[i]] else { return nil }
        if i + 1 < s.count, let a = accidental(s[i + 1]) { return (floorMod(base + a, 12), i + 2) }
        return (base, i + 1)
    }

    /// The parts of a chord symbol, or nil when `token` is not a chord.
    public static func parse(_ token: String) -> Parsed? {
        let s = Array(token)
        guard let (root, afterRoot) = note(s, 0) else { return nil }
        var i = afterRoot
        var depth = 0
        var bass = -1
        scan: while i < s.count {
            let c = s[i]
            if c == "/" {
                if i + 1 < s.count, s[i + 1].isASCII, s[i + 1].isNumber {
                    i += 1
                    continue
                }
                // A bass note must be the last thing in the chord.
                guard let (pc, end) = note(s, i + 1), end == s.count else { return nil }
                bass = pc
                let quality = String(s[afterRoot..<i])
                return depth == 0 ? Parsed(root: root, quality: quality, bass: bass) : nil
            }
            if c.isASCII, c.isNumber {
                i += 1
                continue
            }
            for word in qualityWords {
                let w = Array(word)
                if i + w.count <= s.count, Array(s[i..<(i + w.count)]) == w {
                    if word == "(" { depth += 1 }
                    if word == ")" { depth -= 1 }
                    i += w.count
                    continue scan
                }
            }
            return nil
        }
        // Unbalanced parentheses mean ordinary text, e.g. "A)" in a list.
        return depth == 0 ? Parsed(root: root, quality: String(s[afterRoot...]), bass: bass) : nil
    }

    public static func isChord(_ token: String) -> Bool { parse(token) != nil }

    private static func isMinor(_ quality: String) -> Bool {
        (quality.hasPrefix("m") && !quality.hasPrefix("maj")) || quality.hasPrefix("min")
    }

    /// `chord` moved by `semitones`, spelled with flats or sharps. Other text comes back unchanged.
    public static func transposeChord(_ chord: String, _ semitones: Int, flats: Bool) -> String {
        guard let p = parse(chord) else { return chord }
        let names = flats ? flat : sharp
        var out = names[floorMod(p.root + semitones, 12)] + p.quality
        if p.bass >= 0 { out += "/" + names[floorMod(p.bass + semitones, 12)] }
        return out
    }

    /// Position of the text after a leading label such as "Intro:" or "Refrão:" (0 when there is none).
    private static func afterLabel(_ s: [Character]) -> Int {
        var i = 0
        while i < s.count, s[i] == " " || s[i] == "\t" { i += 1 }
        var words = 0
        while words < 2 {
            let start = i
            while i < s.count, s[i] != " ", s[i] != "\t", s[i] != ":" { i += 1 }
            let length = i - start
            if length == 0 || length > (words == 0 ? 24 : 12) { return 0 }
            words += 1
            if i < s.count, s[i] == ":" { return i + 1 }
            // One single space may separate the two words of a label ("Refrão 2:").
            if words == 1, i + 1 < s.count, s[i] == " " { i += 1 } else { return 0 }
        }
        return 0
    }

    /// Things that may sit between chords in a chord line without being chords.
    private static func isFiller(_ token: [Character]) -> Bool {
        let t = String(token)
        if token.allSatisfy({ "|/\\-–—.%*".contains($0) }) { return true }
        if t == "(" || t == ")" { return true }
        if ["N.C.", "NC", "N.C", "NC."].contains(t) { return true }
        // Repeats: 2x, x2, (2x), (x2), 2.
        var core = token
        if core.first == "(" { core.removeFirst() }
        if core.last == ")" { core.removeLast() }
        if core.first == "x" || core.first == "X" { core.removeFirst() }
        if core.last == "x" || core.last == "X" { core.removeLast() }
        return (1...2).contains(core.count) && core.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func balanced(_ s: [Character], _ from: Int, _ to: Int) -> Bool {
        var depth = 0
        if from <= to {
            for i in from...to {
                if s[i] == "(" { depth += 1 } else if s[i] == ")" { depth -= 1 }
            }
        }
        return depth == 0
    }

    private static func isSpace(_ c: Character) -> Bool { c == " " || c == "\t" }

    private static func chordSpans(_ s: [Character]) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var i = afterLabel(s)
        while i < s.count {
            if isSpace(s[i]) {
                i += 1
                continue
            }
            var end = i
            while end < s.count, !isSpace(s[end]) { end += 1 }
            var from = i
            var to = end - 1
            i = end
            // Parentheses around a group of chords: "(C G Am F) 2x".
            if s[from] == "(" && !balanced(s, from, to) { from += 1 }
            if to >= from && s[to] == ")" && !balanced(s, from, to) { to -= 1 }
            if to < from { continue }
            let token = Array(s[from...to])
            if isChord(String(token)) {
                spans.append(from..<(to + 1))
            } else if isFiller(token) {
                continue
            } else if token.first == "[" && token.last == "]" && token.count >= 2 {
                // A bracketed chord or section name: "[C]" counts, "[Refrão]" is ignored.
                if isChord(String(token[1..<(token.count - 1)])) { spans.append((from + 1)..<to) }
            } else {
                return []
            }
        }
        return spans
    }

    private static func inlineSpans(_ s: [Character]) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var i = 0
        while i < s.count {
            if s[i] == "[" {
                var j = i + 1
                while j < s.count, s[j] != "]", s[j] != "[" { j += 1 }
                if j < s.count, s[j] == "]", j > i + 1, isChord(String(s[(i + 1)..<j])) {
                    spans.append((i + 1)..<j)
                    i = j
                }
            }
            i += 1
        }
        return spans
    }

    /// Character ranges of the chord symbols of a line made only of chords; empty for lyrics.
    public static func chordSpans(_ line: String) -> [Range<Int>] { chordSpans(Array(line)) }

    /// Every chord range of a line, whichever layout it uses.
    public static func spans(_ line: String) -> [Range<Int>] {
        let s = Array(line)
        let aligned = chordSpans(s)
        return aligned.isEmpty ? inlineSpans(s) : aligned
    }

    /// Transposes one line. In chord lines the spacing after each chord grows or shrinks so the
    /// following chords stay above the same syllables.
    public static func transposeLine(_ line: String, _ semitones: Int, flats: Bool) -> String {
        let s = Array(line)
        let alignedSpans = chordSpans(s)
        let aligned = !alignedSpans.isEmpty
        let all = aligned ? alignedSpans : inlineSpans(s)
        if all.isEmpty { return line }
        var out = ""
        var pos = 0
        var debt = 0 // columns the output is ahead (+) of the original
        for span in all {
            var gap = Array(s[pos..<span.lowerBound])
            if aligned && debt != 0 && !gap.isEmpty && gap.allSatisfy(isSpace) {
                if debt > 0 {
                    let cut = min(debt, gap.count - 1)
                    gap.removeFirst(cut)
                    debt -= cut
                } else {
                    gap += Array(repeating: " ", count: -debt)
                    debt = 0
                }
            }
            out += String(gap)
            let old = String(s[span])
            let new = transposeChord(old, semitones, flats: flats)
            out += new
            debt += new.count - old.count
            pos = span.upperBound
        }
        out += String(s[pos...])
        return out
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// The first chord of the sheet, which by convention names its key.
    public static func firstChord(_ text: String) -> String? {
        for line in lines(text) {
            let s = Array(line)
            let aligned = chordSpans(s)
            if let span = (aligned.isEmpty ? inlineSpans(s) : aligned).first { return String(s[span]) }
        }
        return nil
    }

    /// Key of the sheet after moving it by `semitones`, guessed from its first chord.
    public static func keyOf(_ text: String, _ semitones: Int = 0) -> Key? {
        guard let first = firstChord(text), let p = parse(first) else { return nil }
        return Key(floorMod(p.root + semitones, 12), isMinor(p.quality))
    }

    /// Name of a key the way chord sheets write it: "G", "F#m", "Bb".
    public static func keyName(_ key: Key) -> String {
        (key.prefersFlats ? flat : sharp)[key.tonic] + (key.minor ? "m" : "")
    }

    /// The whole sheet moved by `semitones`; flats or sharps follow the resulting key.
    public static func transpose(_ text: String, _ semitones: Int) -> String {
        let steps = floorMod(semitones, 12)
        if steps == 0 { return text }
        let flats = keyOf(text, steps)?.prefersFlats ?? false
        return lines(text).map { transposeLine($0, steps, flats: flats) }.joined(separator: "\n")
    }
}
