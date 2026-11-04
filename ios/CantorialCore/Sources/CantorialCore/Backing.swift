import Foundation

public enum BackingStyle: String, Codable, CaseIterable, Identifiable {
    case harmony = "HARMONY"
    case pad = "PAD"
    case echo = "ECHO"
    case double = "DOUBLE"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .harmony: return "Harmonia"
        case .pad: return "Pad"
        case .echo: return "Resposta"
        case .double: return "Dobra"
        }
    }

    public var summary: String {
        switch self {
        case .harmony: return "Canta a letra junto com o regente, em terças"
        case .pad: return "Notas longas do acorde em \"Uh\" ou \"Ah\""
        case .echo: return "Repete o fim das frases, como um eco"
        case .double: return "Reforça a melodia em uníssono ou oitava"
        }
    }
}

/// Where the backing singer's voice sits compared to the lead singer (regente).
public enum Relation { case higher, lower, same }

public struct BackingPart {
    public let name: String
    public let notes: [NoteEvent]
    public let gainDb: Float
    public let place: String
}

public struct BackingPlan {
    /// The melody placed in the lead singer's register.
    public let lead: [NoteEvent]
    public let leadShift: Int
    public let parts: [BackingPart]
    public let relation: Relation
    public let tips: [String]
}

/// Rounds half up, like Kotlin's roundToInt.
@inline(__always) func roundHalfUp(_ v: Float) -> Int { Int((v + 0.5).rounded(.down)) }

/// Writes backing vocal parts for a melody, taking into account the lead singer's voice type
/// (regente) and the backing singer's range, and suggests how loud each part should be.
public enum Backing {
    public static func relation(lead: VoiceType, singer: ClosedRange<Int>) -> Relation {
        let diff = (singer.lowerBound + singer.upperBound) / 2 - lead.center
        if diff >= 3 { return .higher }
        if diff <= -3 { return .lower }
        return .same
    }

    /// Octave shift that puts the melody where a `lead` voice would sing it.
    public static func leadShift(_ melody: [NoteEvent], lead: VoiceType) -> Int {
        if melody.isEmpty { return 0 }
        return roundHalfUp(Float(lead.center + 2 - Harmony.median(melody)) / 12) * 12
    }

    public static func arrange(_ melody: [NoteEvent], key: Key, style: BackingStyle, lead: VoiceType, singer: ClosedRange<Int>, voices: Int = 1) -> BackingPlan {
        let shift = leadShift(melody, lead: lead)
        let leadLine = melody.map { $0.with(midi: $0.midi + shift) }
        let rel = relation(lead: lead, singer: singer)
        let n = min(max(voices, 1), 2)
        if leadLine.isEmpty { return BackingPlan(lead: leadLine, leadShift: shift, parts: [], relation: rel, tips: []) }
        // In the same register, sing above a melody that sits low and below one that sits high.
        let above: Bool
        switch rel {
        case .higher: above = true
        case .lower: above = false
        case .same: above = Harmony.median(leadLine) <= lead.center
        }
        let raw: [(String, [NoteEvent])]
        switch style {
        case .harmony: raw = harmonyParts(leadLine, key: key, above: above, singer: singer, n: n)
        case .pad: raw = padParts(leadLine, key: key, singer: singer, n: n)
        case .echo: raw = echoParts(leadLine, key: key, above: above, singer: singer, n: n)
        case .double: raw = doubleParts(leadLine, singer: singer, n: n)
        }
        let leadMedian = Harmony.median(leadLine)
        let base: Float
        switch style {
        case .harmony: base = n == 1 ? -6 : -8
        case .pad: base = -10
        case .echo: base = -3
        case .double: base = -9
        }
        var parts: [BackingPart] = []
        for (i, entry) in raw.enumerated() {
            let (name, notes) = entry
            let median = Harmony.median(notes)
            var gain = base
            // High voices cut through more easily, low voices can carry a little more body.
            if median > leadMedian + 4 { gain -= 2 } else if median < leadMedian - 4 { gain += 1 }
            if n == 2 && i == 0 { gain -= 1 }
            let place: String
            if notes.isEmpty {
                place = ""
            } else if median > leadMedian + 2 {
                place = "acima do regente"
            } else if median < leadMedian - 2 {
                place = "abaixo do regente"
            } else {
                place = "na altura do regente"
            }
            parts.append(BackingPart(name: name, notes: notes, gainDb: gain, place: place))
        }
        return BackingPlan(lead: leadLine, leadShift: shift, parts: parts, relation: rel,
                           tips: tips(style: style, rel: rel, lead: lead, singer: singer, parts: parts))
    }

    private static func harmonyParts(_ lead: [NoteEvent], key: Key, above: Bool, singer: ClosedRange<Int>, n: Int) -> [(String, [NoteEvent])] {
        if n == 1 {
            let line = Harmony.guided(lead, key: key, range: singer, preferAbove: above)
            return [(above ? "Backing (3ª acima)" : "Backing (3ª abaixo)", line)]
        }
        // Close-harmony trio: the melody plus two chord tones stacked above or below it.
        var near: [NoteEvent] = []
        var far: [NoteEvent] = []
        for note in lead {
            let m = note.midi
            let deg = key.degreeOf(m)
            let first = Harmony.note(m, key: key, steps: above ? 2 : -2)
            let second: Int
            if deg < 0 {
                second = Harmony.note(first, key: key, steps: above ? 2 : -2)
            } else {
                let rootDeg = above ? deg : floorMod(deg - 4, 7)
                let steps = diminished(rootDeg, key) ? 5 : 4
                second = Harmony.note(m, key: key, steps: above ? steps : -steps)
            }
            near.append(note.with(midi: first))
            far.append(note.with(midi: second))
        }
        let shift = Harmony.octaveFor(near + far, range: singer)
        let a = near.map { $0.with(midi: $0.midi + shift) }
        let b = far.map { $0.with(midi: $0.midi + shift) }
        return above ? [("Backing 1 (agudo)", b), ("Backing 2 (grave)", a)] : [("Backing 1 (agudo)", a), ("Backing 2 (grave)", b)]
    }

    private static let clashes: Set<Int> = [1, 6, 11]

    private static func diminished(_ rootDegree: Int, _ key: Key) -> Bool {
        key.minor ? rootDegree == 1 : rootDegree == 6
    }

    private struct Chunk {
        let start: Int
        let end: Int
        let leadMedian: Int
        let tones: [Int]
        let notes: [NoteEvent]
    }

    private static func padParts(_ lead: [NoteEvent], key: Key, singer: ClosedRange<Int>, n: Int) -> [(String, [NoteEvent])] {
        // Chunks of up to ~1.6 s inside a phrase, each harmonised with one diatonic triad.
        var chunks: [Chunk] = []
        var i = 0
        while i < lead.count {
            var j = i
            while j + 1 < lead.count && lead[j + 1].endMs - lead[i].startMs <= 1600 && lead[j + 1].startMs - lead[j].endMs < 700 { j += 1 }
            let notes = Array(lead[i...j])
            var bestRoot = 0
            var bestScore: Float = -1
            for root in 0..<7 {
                let degrees = [root, (root + 2) % 7, (root + 4) % 7]
                var cover: Float = 0
                for nt in notes {
                    let d = key.degreeOf(nt.midi)
                    // Chord tones count; a melody note on the chord's root counts a little more.
                    if degrees.contains(d) { cover += Float(nt.durMs) * (d == root ? 1.1 : 1) }
                }
                switch root {
                case 0, 3, 4: cover *= 1.15
                case 5: cover *= 1.05
                default: if diminished(root, key) { cover *= 0.7 }
                }
                if cover > bestScore {
                    bestScore = cover
                    bestRoot = root
                }
            }
            let tones = [bestRoot, (bestRoot + 2) % 7, (bestRoot + 4) % 7].map { key.tonic + key.scale[$0] }
            chunks.append(Chunk(start: notes[0].startMs, end: notes[notes.count - 1].endMs, leadMedian: Harmony.median(notes), tones: tones, notes: notes))
            i = j + 1
        }
        let center = Float(singer.lowerBound + singer.upperBound) / 2
        func line(_ below: [Int]?) -> [Int] {
            Harmony.viterbi(
                chunks.count,
                candidates: { k in
                    ((singer.lowerBound - 2)...(singer.upperBound + 2)).filter { p in
                        chunks[k].tones.contains { floorMod(p - $0, 12) == 0 }
                    }
                },
                cost: { k, prev, c in
                    let ch = chunks[k]
                    var cost = Harmony.rangeCost(c, singer, center)
                    if abs(c - ch.leadMedian) < 1 { cost += 2 }
                    // Avoid harsh clashes (semitones, sevenths, tritones) with passing melody notes.
                    let total = Float(max(ch.end - ch.start, 1))
                    for nt in ch.notes where clashes.contains(abs(c - nt.midi) % 12) {
                        cost += 2.5 * Float(nt.durMs) / total
                    }
                    // Prefer the third (colour), then the fifth, then the root.
                    if floorMod(c - ch.tones[0], 12) == 0 { cost += 1.2 }
                    if floorMod(c - ch.tones[2], 12) == 0 { cost += 0.8 }
                    if let below = below, c > below[k] - 3 { cost += 6 }
                    if prev != Harmony.noPrev { cost += 0.25 * Float(abs(c - prev)) }
                    return cost
                }
            )
        }
        func notes(_ path: [Int]) -> [NoteEvent] {
            Harmony.merge(chunks.enumerated().map { k, ch in NoteEvent(ch.start, max(ch.end - ch.start - 80, 120), path[k]) }, maxGapMs: 150)
        }
        let first = line(nil)
        if n == 2 {
            return [("Pad agudo (Uh)", notes(first)), ("Pad grave (Uh)", notes(line(first)))]
        }
        return [("Pad (Uh)", notes(first))]
    }

    private static func echoParts(_ lead: [NoteEvent], key: Key, above: Bool, singer: ClosedRange<Int>, n: Int) -> [(String, [NoteEvent])] {
        let phrases = Phrases.split(lead)
        var echo: [NoteEvent] = []
        for (p, ph) in phrases.enumerated() {
            let next = p + 1 < phrases.count ? phrases[p + 1].startMs : ph.endMs + 2400
            let gap = next - ph.endMs
            if gap < 700 { continue }
            let length = min(gap - 250, 1800)
            var tail = lead.filter { $0.startMs >= ph.startMs && $0.startMs < ph.endMs && $0.startMs >= ph.endMs - length }
            if tail.isEmpty, let last = lead.last(where: { $0.startMs < ph.endMs }) { tail = [last] }
            if tail.isEmpty { continue }
            let offset = ph.endMs + 150 - tail[0].startMs
            for t in tail {
                let start = t.startMs + offset
                let dur = min(t.durMs, next - 100 - start)
                if dur >= 80 { echo.append(NoteEvent(start, dur, t.midi)) }
            }
        }
        if echo.isEmpty { return [] }
        let unison = Harmony.fitOctave(echo, range: singer)
        if n == 1 { return [("Resposta", unison)] }
        return [("Resposta", unison), ("Resposta (3ª)", Harmony.guided(unison, key: key, range: singer, preferAbove: above))]
    }

    private static func doubleParts(_ lead: [NoteEvent], singer: ClosedRange<Int>, n: Int) -> [(String, [NoteEvent])] {
        let unison = Harmony.fitOctave(lead, range: singer)
        if n == 1 { return [("Dobra", unison)] }
        let up = Harmony.median(unison) + 12 <= singer.upperBound + 2
        let octave = unison.map { $0.with(midi: $0.midi + (up ? 12 : -12)) }
        return up ? [("Dobra (8ª acima)", octave), ("Dobra", unison)] : [("Dobra", unison), ("Dobra (8ª abaixo)", octave)]
    }

    private static func tips(style: BackingStyle, rel: Relation, lead: VoiceType, singer: ClosedRange<Int>, parts: [BackingPart]) -> [String] {
        var tips: [String] = []
        let singerType = VoiceType.classify(singer.lowerBound, singer.upperBound)
        let gain = parts.first.map { roundHalfUp($0.gainDb) } ?? -6
        tips.append("Fique cerca de \(-gain) dB abaixo do regente: a melodia vem na frente, o backing é a moldura.")
        switch rel {
        case .higher:
            tips.append("Sua voz (\(singerType.label)) é mais aguda que a do regente (\(lead.label)). Agudos se destacam: use voz leve, pouco vibrato e segure o volume.")
        case .lower:
            tips.append("Sua voz (\(singerType.label)) é mais grave que a do regente (\(lead.label)). Você é a base: pode usar um pouco mais de corpo, sem cobrir a melodia.")
        case .same:
            tips.append("Você (\(singerType.label)) e o regente (\(lead.label)) estão na mesma região. Mantenha a sua linha firme para não escorregar para a melodia dele.")
        }
        if lead.female != singerType.female {
            tips.append("Vozes masculina e feminina soam uma oitava deslocadas: a terça vira décima. Fica aberto e bonito, desde que o backing esteja mais baixo.")
        }
        switch style {
        case .harmony: tips.append("Pronuncie igual ao regente: mesmas vogais, mesmas respirações e finais cortados juntos.")
        case .pad: tips.append("Use \"Uh\" para um som macio ou \"Ah\" para mais brilho. Entre e saia sem ataque, como um órgão.")
        case .echo: tips.append("A resposta pode vir quase no volume do regente, mas só depois que ele termina a frase.")
        case .double: tips.append("Na dobra ninguém deve perceber duas vozes: copie o timbre, tire o vibrato e cante um pouco atrás.")
        }
        if parts.count == 2 { tips.append("Com duas vozes de backing, a mais aguda canta 1 dB mais suave para não chamar atenção.") }
        tips.append("No palco, fique um pouco mais longe do microfone que o regente e acompanhe a dinâmica dele: ele cresce, você cresce junto.")
        return tips
    }
}
