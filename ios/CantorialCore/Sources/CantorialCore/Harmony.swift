import Foundation

/// The kinds of second voice the app can write and teach.
public enum HarmonyMode: String, Codable, CaseIterable, Identifiable {
    case thirdAbove = "THIRD_ABOVE"
    case thirdBelow = "THIRD_BELOW"
    case sixthBelow = "SIXTH_BELOW"
    case sixthAbove = "SIXTH_ABOVE"
    case guided = "GUIDED"
    case contrary = "CONTRARY"
    case pedal = "PEDAL"
    case unison = "UNISON"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .thirdAbove: return "3ª acima"
        case .thirdBelow: return "3ª abaixo"
        case .sixthBelow: return "6ª abaixo"
        case .sixthAbove: return "6ª acima"
        case .guided: return "Conduzida"
        case .contrary: return "Contrária"
        case .pedal: return "Nota pedal"
        case .unison: return "Dobra"
        }
    }

    public var summary: String {
        switch self {
        case .thirdAbove: return "Paralela, logo acima da melodia"
        case .thirdBelow: return "Paralela, logo abaixo da melodia"
        case .sixthBelow: return "A 3ª acima levada uma oitava para baixo"
        case .sixthAbove: return "A 3ª abaixo levada uma oitava para cima"
        case .guided: return "Alterna 3ª e 6ª para andar pouco e caber na sua voz"
        case .contrary: return "Anda no sentido oposto ao da melodia"
        case .pedal: return "Segura uma nota enquanto a melodia anda"
        case .unison: return "A mesma melodia, em uníssono ou oitava"
        }
    }

    /// 1 = first steps, 3 = advanced.
    public var level: Int {
        switch self {
        case .thirdAbove, .thirdBelow, .unison: return 1
        case .sixthBelow, .sixthAbove, .guided, .pedal: return 2
        case .contrary: return 3
        }
    }

    var steps: Int {
        switch self {
        case .thirdAbove, .sixthBelow: return 2
        case .thirdBelow, .sixthAbove: return -2
        default: return 0
        }
    }

    var octave: Int {
        switch self {
        case .sixthBelow: return -12
        case .sixthAbove: return 12
        default: return 0
        }
    }

    /// Parallel voices move with the melody and accept a manual octave shift.
    public var parallel: Bool { steps != 0 }
}

/// Second-voice writer. Parallel types move every note by a diatonic third (or sixth); the
/// others choose, note by note, the best candidate pitch with a small Viterbi search.
public enum Harmony {
    static let noPrev = Int.min

    /// Second voice for `melody`. `range` is the singer's range: the non-parallel types stay
    /// inside it. `octaveShift` is applied to parallel types only.
    public static func voice(_ melody: [NoteEvent], key: Key, mode: HarmonyMode, octaveShift: Int = 0, range: ClosedRange<Int>? = nil) -> [NoteEvent] {
        if melody.isEmpty { return [] }
        switch mode {
        case .thirdAbove, .thirdBelow, .sixthBelow, .sixthAbove:
            return melody.map { $0.with(midi: note($0.midi, key: key, steps: mode.steps) + mode.octave + octaveShift) }
        case .guided:
            return guided(melody, key: key, range: range ?? around(melody, 3), preferAbove: nil)
        case .contrary:
            return contrary(melody, key: key, range: range ?? around(melody, -2))
        case .pedal:
            return pedal(melody, key: key, range: range ?? around(melody, -5))
        case .unison:
            return fitOctave(melody, range: range)
        }
    }

    /// Moves `midi` by `steps` scale degrees within `key`; chromatic notes get a sensible third.
    public static func note(_ midi: Int, key: Key, steps: Int) -> Int {
        let scale = key.scale
        let rel = floorMod(midi - key.tonic, 12)
        if let degree = scale.firstIndex(of: rel) {
            let target = degree + steps
            let octaves = floorDiv(target, 7)
            let idx = floorMod(target, 7)
            return midi + scale[idx] + 12 * octaves - scale[degree]
        }
        // Raised notes (leading tones, secondary dominants) take a minor third above;
        // lowered notes (borrowed chords) take a major third above.
        let raised = key.minor ? minorRaised.contains(rel) : majorRaised.contains(rel)
        let third: Int
        if steps > 0 { third = raised ? 3 : 4 } else { third = raised ? -4 : -3 }
        let extraOctaves = steps > 0 ? (steps - 2) / 7 : (steps + 2) / 7
        return midi + third + 12 * extraOctaves
    }

    /// Thirds/sixths that keep the voice smooth and inside `range`. `preferAbove` = true keeps
    /// the line above the melody (false below, nil free), used by backing vocals.
    public static func guided(_ melody: [NoteEvent], key: Key, range: ClosedRange<Int>, preferAbove: Bool?) -> [NoteEvent] {
        let center = Float(range.lowerBound + range.upperBound) / 2
        let path = viterbi(
            melody.count,
            candidates: { i in
                let m = melody[i].midi
                let up = note(m, key: key, steps: 2)
                let down = note(m, key: key, steps: -2)
                return [up, up - 12, up + 12, down, down + 12, down - 12]
            },
            cost: { i, prev, c in
                let m = melody[i].midi
                var cost = rangeCost(c, range, center)
                if preferAbove == true && c < m { cost += 4 }
                if preferAbove == false && c > m { cost += 4 }
                if prev != noPrev {
                    let leap = abs(c - prev)
                    let joined = melody[i].startMs - melody[i - 1].endMs < 600
                    let weight: Float = joined ? 0.45 : 0.15
                    cost += weight * Float(leap)
                    if leap > 7 && joined { cost += 3 }
                    if (c > m) != (prev > melody[i - 1].midi) { cost += 1.5 }
                }
                return cost
            }
        )
        return melody.enumerated().map { $0.element.with(midi: path[$0.offset]) }
    }

    private static func contrary(_ melody: [NoteEvent], key: Key, range: ClosedRange<Int>) -> [NoteEvent] {
        let center = Float(range.lowerBound + range.upperBound) / 2
        let path = viterbi(
            melody.count,
            candidates: { i in
                let m = melody[i].midi
                var list: [Int] = []
                for c in (m - 16)...(m + 16) {
                    if c == m || key.degreeOf(c) < 0 { continue }
                    if intervalCost(abs(c - m)) < 9 { list.append(c) }
                }
                // Chromatic melody notes still get their thirds.
                for t in [note(m, key: key, steps: 2), note(m, key: key, steps: -2)] where !list.contains(t) {
                    list.append(t)
                }
                return list
            },
            cost: { i, prev, c in
                let m = melody[i].midi
                var cost = intervalCost(abs(c - m)) + rangeCost(c, range, center)
                if prev != noPrev {
                    let pm = melody[i - 1].midi
                    let dm = m - pm
                    let dc = c - prev
                    cost += 0.3 * Float(abs(dc))
                    if abs(dc) > 5 { cost += 2 }
                    if dm != 0 {
                        if dc == 0 {
                            cost -= 0.3
                        } else if (dc > 0) != (dm > 0) {
                            cost -= 1.4
                        } else {
                            cost += 0.8
                        }
                        let now = abs(c - m) % 12
                        let before = abs(prev - pm) % 12
                        if dc != 0 && (now == 0 || now == 7) && now == before { cost += 5 }
                    } else if dc == 0 {
                        cost -= 0.2
                    }
                }
                return cost
            }
        )
        return melody.enumerated().map { $0.element.with(midi: path[$0.offset]) }
    }

    /// Cost of a vertical interval for a two-voice texture (thirds and sixths are best).
    private static func intervalCost(_ semitones: Int) -> Float {
        switch semitones {
        case 3, 4, 8, 9, 15, 16: return 0
        case 7: return 0.8
        case 12: return 1.5
        default: return 10
        }
    }

    private static func pedal(_ melody: [NoteEvent], key: Key, range: ClosedRange<Int>) -> [NoteEvent] {
        let center = (range.lowerBound + range.upperBound) / 2
        var out: [NoteEvent] = []
        var i = 0
        for ph in Phrases.split(melody) {
            let from = i
            while i < melody.count && melody[i].startMs < ph.endMs { i += 1 }
            let notes = Array(melody[from..<i])
            if notes.isEmpty { continue }
            // Candidates: tonic, fifth and third of the key, in every octave of the range.
            var best = center
            var bestScore = -Float.greatestFiniteMagnitude
            for degree in [0, 4, 2] {
                let pc = key.tonic + key.scale[degree]
                for p in range where floorMod(p - pc, 12) == 0 {
                    var score: Float = 0
                    for n in notes { score += Float(n.durMs) * pedalConsonance(abs(n.midi - p) % 12) }
                    score -= 3 * Float(abs(p - center))
                    if degree != 0 { score -= 40 }
                    if score > bestScore {
                        bestScore = score
                        best = p
                    }
                }
            }
            for n in notes {
                let h: Int
                if pedalConsonance(abs(n.midi - best) % 12) >= 0.6 {
                    h = best
                } else {
                    // Clash: step out to the nearest third, then come back to the pedal.
                    let t = note(n.midi, key: key, steps: best < n.midi ? -2 : 2)
                    h = [t, t - 12, t + 12].min { abs($0 - best) < abs($1 - best) }!
                }
                out.append(n.with(midi: h))
            }
        }
        return merge(out, maxGapMs: 400)
    }

    private static func pedalConsonance(_ ic: Int) -> Float {
        switch ic {
        case 0, 3, 4, 7: return 1
        case 8, 9: return 0.9
        case 5: return 0.6
        default: return 0
        }
    }

    /// Shifts the whole line by octaves so it sits in `range` (unchanged when nil).
    public static func fitOctave(_ line: [NoteEvent], range: ClosedRange<Int>?) -> [NoteEvent] {
        guard let range = range, !line.isEmpty else { return line }
        let shift = octaveFor(line, range: range)
        return shift == 0 ? line : line.map { $0.with(midi: $0.midi + shift) }
    }

    /// Octave shift (multiple of 12) that keeps most of `line` inside `range`.
    public static func octaveFor(_ line: [NoteEvent], range: ClosedRange<Int>) -> Int {
        let shifts = (-3...3).map { $0 * 12 }
        func cost(_ shift: Int) -> Int {
            var outside = 0
            for n in line {
                let m = n.midi + shift
                let d = m < range.lowerBound ? range.lowerBound - m : (m > range.upperBound ? m - range.upperBound : 0)
                outside += d * n.durMs
            }
            return outside * 10 + abs(shift)
        }
        return shifts.min { cost($0) < cost($1) }!
    }

    /// Joins consecutive notes of equal pitch separated by at most `maxGapMs`.
    public static func merge(_ notes: [NoteEvent], maxGapMs: Int) -> [NoteEvent] {
        guard var cur = notes.first else { return notes }
        var out: [NoteEvent] = []
        for n in notes.dropFirst() {
            if n.midi == cur.midi && n.startMs - cur.endMs <= maxGapMs {
                cur = NoteEvent(cur.startMs, n.endMs - cur.startMs, cur.midi)
            } else {
                out.append(cur)
                cur = n
            }
        }
        out.append(cur)
        return out
    }

    static func rangeCost(_ c: Int, _ range: ClosedRange<Int>, _ center: Float) -> Float {
        let outside: Int
        if c < range.lowerBound { outside = range.lowerBound - c } else if c > range.upperBound { outside = c - range.upperBound } else { outside = 0 }
        return 3 * Float(outside) + 0.04 * abs(Float(c) - center)
    }

    /// A plausible range around the melody, used when the singer's range is unknown.
    private static func around(_ melody: [NoteEvent], _ offset: Int) -> ClosedRange<Int> {
        let m = median(melody) + offset
        return (m - 9)...(m + 9)
    }

    /// Minimum-cost path through per-note candidate pitches. `cost` gets `noPrev` as prev for the first note.
    static func viterbi(_ n: Int, candidates: (Int) -> [Int], cost: (_ i: Int, _ prev: Int, _ c: Int) -> Float) -> [Int] {
        if n == 0 { return [] }
        let cands = (0..<n).map { candidates($0) }
        var score = cands.map { [Float](repeating: 0, count: $0.count) }
        var back = cands.map { [Int](repeating: 0, count: $0.count) }
        for j in 0..<cands[0].count { score[0][j] = cost(0, noPrev, cands[0][j]) }
        if n > 1 {
            for i in 1..<n {
                for j in 0..<cands[i].count {
                    var best = Float.greatestFiniteMagnitude
                    var arg = 0
                    for k in 0..<cands[i - 1].count {
                        let s = score[i - 1][k] + cost(i, cands[i - 1][k], cands[i][j])
                        if s < best {
                            best = s
                            arg = k
                        }
                    }
                    score[i][j] = best
                    back[i][j] = arg
                }
            }
        }
        var j = score[n - 1].indices.min { score[n - 1][$0] < score[n - 1][$1] } ?? 0
        var out = [Int](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            out[i] = cands[i][j]
            j = back[i][j]
        }
        return out
    }

    /// Median pitch of a line.
    public static func median(_ line: [NoteEvent]) -> Int {
        if line.isEmpty { return 60 }
        let s = line.map { $0.midi }.sorted()
        return s[s.count / 2]
    }

    private static let majorRaised: Set<Int> = [1, 6]
    private static let minorRaised: Set<Int> = [4, 6, 9, 11]
}
