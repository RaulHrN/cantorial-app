import Foundation

public struct NoteEvent: Codable, Hashable {
    public var startMs: Int
    public var durMs: Int
    public var midi: Int

    public init(_ startMs: Int, _ durMs: Int, _ midi: Int) {
        self.startMs = startMs
        self.durMs = durMs
        self.midi = midi
    }

    public var endMs: Int { startMs + durMs }

    public func with(midi: Int) -> NoteEvent { NoteEvent(startMs, durMs, midi) }
}

/// Rounds to the nearest integer, ties towards +infinity (like Kotlin roundToInt).
@inline(__always) func roundInt(_ v: Float) -> Int {
    let f = v.rounded(.down)
    return Int(v - f >= 0.5 ? f + 1 : f)
}

/// Turns a frame-by-frame pitch track (MIDI, NaN = unvoiced) into discrete notes.
public enum Segmenter {
    public static func segment(
        _ track: [Float],
        hopMs: Float,
        firstFrameMs: Float = 0,
        minNoteMs: Int = 90,
        correctTuning: Bool = true,
        onsets: [Bool]? = nil
    ) -> [NoteEvent] {
        let n = track.count
        if n == 0 { return [] }
        var f = track

        // Bridge tiny dropouts (up to 2 frames) inside a stable sound.
        var i = 1
        while i < n {
            if f[i].isNaN && !f[i - 1].isNaN {
                var j = i
                while j < n && f[j].isNaN && j - i < 3 { j += 1 }
                let reattack = onsets?[min(j, n - 1)] ?? false
                if j < n && j - i <= 2 && !f[j].isNaN && abs(f[j] - f[i - 1]) < 1 && !reattack {
                    for k in i..<j {
                        f[k] = f[i - 1] + (f[j] - f[i - 1]) * Float(k - i + 1) / Float(j - i + 1)
                    }
                }
                i = j
            } else {
                i += 1
            }
        }

        var smooth = medianFilter(f, width: 5)

        // Global tuning offset (circular mean of the deviation from equal temperament).
        var offset: Float = 0
        if correctTuning {
            var c = 0.0
            var s = 0.0
            for v in smooth where !v.isNaN {
                let a = 2.0 * Double.pi * Double(v - Float(roundInt(v)))
                c += cos(a)
                s += sin(a)
            }
            if c != 0 || s != 0 {
                let o = Float(atan2(s, c) / (2.0 * Double.pi))
                if abs(o) > 0.08 { offset = o }
            }
        }
        for k in 0..<n where !smooth[k].isNaN { smooth[k] -= offset }

        var notes: [NoteEvent] = []
        var attacked: [Bool] = []
        let maxGap = 3
        let changeFrames = 3
        var segStart = -1
        var lastVoiced = -1
        var center: Float = 0
        var devStart = -1
        var lastOnset = -1
        var lastEnd = -1

        func close(_ a: Int, _ b: Int) {
            if a < 0 || b < a { return }
            lastEnd = b
            let values = smooth[a...b].filter { !$0.isNaN }
            if values.isEmpty { return }
            let durMs = roundInt(Float(b - a + 1) * hopMs)
            if durMs < minNoteMs { return }
            let pitch = roundInt(median(values))
            notes.append(NoteEvent(roundInt(firstFrameMs + Float(a) * hopMs), durMs, pitch))
            attacked.append(onsets?[a] ?? false)
        }

        for k in 0..<n {
            let v = smooth[k]
            if onsets?[k] == true { lastOnset = k }
            if v.isNaN {
                if segStart >= 0 && k - lastVoiced > maxGap {
                    close(segStart, lastVoiced)
                    segStart = -1
                    devStart = -1
                }
                continue
            }
            if segStart >= 0 && onsets?[k] == true && k - segStart >= 3 {
                // Re-articulation (a consonant or breath) on the same or another pitch.
                close(segStart, lastVoiced)
                segStart = -1
            }
            if segStart < 0 {
                // Start at the attack when the pitch only became clear a few frames later.
                segStart = (lastOnset > lastEnd && lastOnset <= k && k - lastOnset <= 5) ? lastOnset : k
                center = v
                devStart = -1
                lastVoiced = k
                continue
            }
            // Refine the reference pitch while the note is young (onsets often glide).
            if k - segStart >= 1 && k - segStart <= 5 && devStart < 0 {
                center = median(smooth[segStart...k].filter { !$0.isNaN })
            }
            if abs(v - center) > 0.75 {
                if devStart < 0 { devStart = k }
                if k - devStart + 1 >= changeFrames {
                    // A too-short first part is an onset glide: it belongs to the new note.
                    if Float(devStart - segStart) * hopMs >= Float(minNoteMs) {
                        close(segStart, devStart - 1)
                        segStart = devStart
                    }
                    center = median(smooth[devStart...k].filter { !$0.isNaN })
                    devStart = -1
                }
            } else {
                devStart = -1
            }
            lastVoiced = k
        }
        if segStart >= 0 { close(segStart, lastVoiced) }
        return mergeRepeats(notes, gapMs: roundInt(hopMs * 3), attacked: attacked)
    }

    /// Joins consecutive notes of the same pitch separated by a very short gap,
    /// unless the second one was clearly re-attacked.
    public static func mergeRepeats(_ notes: [NoteEvent], gapMs: Int, attacked: [Bool]? = nil) -> [NoteEvent] {
        guard var cur = notes.first else { return notes }
        var out: [NoteEvent] = []
        out.reserveCapacity(notes.count)
        for k in 1..<max(1, notes.count) where k < notes.count {
            let nx = notes[k]
            let reattack = (attacked != nil && k < attacked!.count) ? attacked![k] : false
            if nx.midi == cur.midi && nx.startMs - cur.endMs <= gapMs && !reattack {
                cur = NoteEvent(cur.startMs, nx.endMs - cur.startMs, cur.midi)
            } else {
                out.append(cur)
                cur = nx
            }
        }
        out.append(cur)
        return out
    }

    private static func medianFilter(_ src: [Float], width: Int) -> [Float] {
        let half = width / 2
        var out = [Float](repeating: .nan, count: src.count)
        var tmp: [Float] = []
        tmp.reserveCapacity(width)
        for k in 0..<src.count where !src[k].isNaN {
            tmp.removeAll(keepingCapacity: true)
            for j in (k - half)...(k + half) where j >= 0 && j < src.count && !src[j].isNaN {
                tmp.append(src[j])
            }
            out[k] = median(tmp)
        }
        return out
    }

    /// Marks frames where the level jumps by at least `riseDb` over the previous few frames:
    /// the start of a sung syllable. Used to keep repeated notes apart.
    public static func onsets(_ levelsDb: [Float], riseDb: Float = 8, minDb: Float = -60) -> [Bool] {
        var out = [Bool](repeating: false, count: levelsDb.count)
        for i in 0..<levelsDb.count {
            if levelsDb[i] < minDb { continue }
            var low = Float.greatestFiniteMagnitude
            for j in max(0, i - 4)..<i { low = min(low, levelsDb[j]) }
            if low == .greatestFiniteMagnitude { continue }
            let recent = (i >= 1 && out[i - 1]) || (i >= 2 && out[i - 2])
            if levelsDb[i] - low >= riseDb && !recent { out[i] = true }
        }
        return out
    }

    static func median(_ values: [Float]) -> Float {
        if values.isEmpty { return .nan }
        let s = values.sorted()
        let c = s.count
        return c % 2 == 1 ? s[c / 2] : (s[c / 2 - 1] + s[c / 2]) / 2
    }
}

/// Krumhansl-Schmuckler key finding, weighted by note duration.
public enum KeyDetector {
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    public static func detect(_ notes: [NoteEvent]) -> Key {
        var hist = [Double](repeating: 0, count: 12)
        for n in notes { hist[Pitch.pitchClass(n.midi)] += Double(n.durMs) }
        if hist.reduce(0, +) == 0 { return Key(0, false) }
        var best = Key(0, false)
        var bestR = -Double.greatestFiniteMagnitude
        for tonic in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? minorProfile : majorProfile
                let r = correlation(hist) { pc in profile[floorMod(pc - tonic, 12)] }
                if r > bestR {
                    bestR = r
                    best = Key(tonic, minor)
                }
            }
        }
        return best
    }

    private static func correlation(_ x: [Double], _ y: (Int) -> Double) -> Double {
        let mx = x.reduce(0, +) / 12
        var my = 0.0
        for i in 0..<12 { my += y(i) }
        my /= 12
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<12 {
            let a = x[i] - mx
            let b = y(i) - my
            num += a * b
            dx += a * a
            dy += b * b
        }
        return (dx == 0 || dy == 0) ? 0 : num / (dx * dy).squareRoot()
    }
}

public struct Phrase: Hashable {
    public let startMs: Int
    public let endMs: Int
}

public enum Phrases {
    /// Splits a melody at rests longer than `gapMs`, keeping phrases shorter than `maxMs`.
    public static func split(_ notes: [NoteEvent], gapMs: Int = 650, maxMs: Int = 14000) -> [Phrase] {
        guard let first = notes.first else { return [] }
        var out: [Phrase] = []
        var start = first.startMs
        var end = first.endMs
        for n in notes.dropFirst() {
            if n.startMs - end > gapMs || n.endMs - start > maxMs {
                out.append(Phrase(startMs: start, endMs: end))
                start = n.startMs
            }
            end = max(end, n.endMs)
        }
        out.append(Phrase(startMs: start, endMs: end))
        return out
    }
}

/// Parses a typed melody such as "Dó Ré Mi:2 - Fá#4 Sol/0.5" or "C D E:2 F#4".
public enum Notation {
    public struct Result {
        public let notes: [NoteEvent]
        public let error: String?
    }

    private static let solfege: [(String, Int)] = [("sol", 7), ("do", 0), ("re", 2), ("mi", 4), ("fa", 5), ("la", 9), ("si", 11)]
    private static let letters: [Character: Int] = ["c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11]

    public static func parse(_ text: String, bpm: Int) -> Result {
        let beatMs = 60000 / Float(min(max(bpm, 30), 300))
        let separators = CharacterSet(charactersIn: " ,;\n\t|")
        let tokens = text.components(separatedBy: separators).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var notes: [NoteEvent] = []
        var t: Float = 0
        var prev = 60
        var lastBeats: Float = 1
        for raw in tokens {
            let parts = raw.split(whereSeparator: { $0 == ":" || $0 == "/" }).map(String.init)
            if parts.count > 2 || parts.isEmpty { return Result(notes: notes, error: "Não entendi \"\(raw)\"") }
            var beats = lastBeats
            if parts.count == 2 {
                guard let b = Float(parts[1].replacingOccurrences(of: ",", with: ".")), b > 0, b <= 64 else {
                    return Result(notes: notes, error: "Duração inválida em \"\(raw)\"")
                }
                beats = b
            }
            lastBeats = beats
            let head = normalize(parts[0])
            if head == "-" || head == "p" || head == "pausa" {
                t += beats * beatMs
                continue
            }
            guard let midi = parseNote(head, prev: prev) else {
                return Result(notes: notes, error: "Não entendi a nota \"\(raw)\"")
            }
            notes.append(NoteEvent(roundInt(t), roundInt(beats * beatMs * 0.95), midi))
            prev = midi
            t += beats * beatMs
        }
        if notes.isEmpty { return Result(notes: notes, error: "Digite pelo menos uma nota") }
        return Result(notes: notes, error: nil)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "ó", with: "o")
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "á", with: "a")
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
    }

    private static func parseNote(_ s: String, prev: Int) -> Int? {
        var rest: Substring
        var pc: Int
        if let sol = solfege.first(where: { s.hasPrefix($0.0) }) {
            pc = sol.1
            rest = s.dropFirst(sol.0.count)
        } else {
            guard let first = s.first, let v = letters[first] else { return nil }
            pc = v
            rest = s.dropFirst()
        }
        while let ch = rest.first, ch == "#" || ch == "b" {
            pc += ch == "#" ? 1 : -1
            rest = rest.dropFirst()
        }
        if rest.isEmpty {
            // Pick the octave that lands closest to the previous note.
            let base = floorMod(pc, 12)
            var best = base
            var bestDist = Int.max
            for oct in 0...9 {
                let m = base + 12 * oct
                let d = abs(m - prev)
                if d < bestDist {
                    bestDist = d
                    best = m
                }
            }
            return min(max(best, 24), 96)
        }
        guard let octave = Int(rest), octave >= 0, octave <= 8 else { return nil }
        return min(max(pc + 12 * (octave + 1), 12), 120)
    }
}
