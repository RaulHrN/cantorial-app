import Foundation

/// How a note in a practice timeline is used.
public enum Role {
    /// Played by the app for the singer to hear first.
    case listen
    /// What the singer must sing. Scored, and only played when the guide is on.
    case target
    /// Played while the singer sings (e.g. the melody under a second voice).
    case accomp
}

public struct TimedNote {
    public let startMs: Int
    public let durMs: Int
    public let midi: Int
    public let role: Role
    public let gain: Float

    public init(_ startMs: Int, _ durMs: Int, _ midi: Int, _ role: Role, gain: Float = 1) {
        self.startMs = startMs
        self.durMs = durMs
        self.midi = midi
        self.role = role
        self.gain = gain
    }

    public var endMs: Int { startMs + durMs }
}

public struct Timeline {
    public let notes: [TimedNote]
    public let lengthMs: Int
    public let singStartMs: Int
    public let targets: [TimedNote]

    public init(notes: [TimedNote], lengthMs: Int, singStartMs: Int) {
        self.notes = notes
        self.lengthMs = lengthMs
        self.singStartMs = singStartMs
        targets = notes.filter { $0.role == .target }
    }
}

public enum ExerciseKind: String, Codable {
    case pattern = "PATTERN"
    case sustain = "SUSTAIN"
    case echo = "ECHO"
    case breath = "BREATH"
    case balance = "BALANCE"
}

public struct Exercise: Codable, Identifiable {
    public let id: String
    public let title: String
    public let category: String
    public let summary: String
    public let steps: [String]
    public let kind: ExerciseKind
    /// Semitone offsets from the root (major scale based); nil is a rest.
    public let pattern: [Int?]
    /// Beats per note; defaults to one beat each.
    public let beats: [Float]?
    public let bpm: Int
    /// Fraction of each beat that sounds (1 = legato, 0.4 = staccato).
    public let legato: Float
    public let harmony: HarmonyMode?
    public let backing: BackingStyle?
    public let backingVoices: Int
    public let backingPart: Int
    /// Semitones the root moves between repetitions.
    public let rootStep: Int
    public let minutes: Int
    public let needsHeadphones: Bool

    public init(
        id: String, title: String = "", category: String = "", summary: String = "", steps: [String] = [],
        kind: ExerciseKind = .pattern, pattern: [Int?] = [0], beats: [Float]? = nil, bpm: Int = 90, legato: Float = 0.92,
        harmony: HarmonyMode? = nil, backing: BackingStyle? = nil, backingVoices: Int = 1, backingPart: Int = 0,
        rootStep: Int = 1, minutes: Int = 3, needsHeadphones: Bool = false
    ) {
        self.id = id; self.title = title; self.category = category; self.summary = summary; self.steps = steps
        self.kind = kind; self.pattern = pattern; self.beats = beats; self.bpm = bpm; self.legato = legato
        self.harmony = harmony; self.backing = backing; self.backingVoices = backingVoices; self.backingPart = backingPart
        self.rootStep = rootStep; self.minutes = minutes; self.needsHeadphones = needsHeadphones
    }
}

public func dbToGain(_ db: Float) -> Float { Float(pow(10.0, Double(db) / 20.0)) }

public enum ExerciseTimeline {
    private static let leadInMs = 400
    private static let tailMs = 700

    private struct Line {
        let notes: [NoteEvent]
        let gain: Float
        let target: Bool
    }

    /// Melody of a pattern exercise, starting at time 0.
    public static func melody(_ ex: Exercise, root: Int) -> [NoteEvent] {
        let beatMs = 60000 / Float(ex.bpm)
        var out: [NoteEvent] = []
        var t: Float = 0
        for (i, offset) in ex.pattern.enumerated() {
            let b = (ex.beats != nil && i < ex.beats!.count) ? ex.beats![i] : 1
            if let offset = offset {
                out.append(NoteEvent(roundInt(t), roundInt(b * beatMs * ex.legato), root + offset))
            }
            t += b * beatMs
        }
        return out
    }

    /// `range` is the singer's range; `lead` is the lead singer's voice type in backing exercises.
    public static func build(_ ex: Exercise, root: Int, range: ClosedRange<Int>? = nil, lead: VoiceType? = nil) -> Timeline {
        let range = range ?? (root - 5)...(root + 19)
        let beatMs = 60000 / Float(ex.bpm)
        let key = Key(floorMod(root, 12), false)
        var notes: [TimedNote] = []
        switch ex.kind {
        case .sustain:
            notes.append(TimedNote(leadInMs, 1500, root, .listen))
            let sing = leadInMs + 1500 + 900
            notes.append(TimedNote(sing, 5000, root, .target))
            return Timeline(notes: notes, lengthMs: sing + 5000 + tailMs, singStartMs: sing)
        case .echo:
            notes.append(TimedNote(leadInMs, 1200, root, .listen))
            let sing = leadInMs + 1200 + 700
            notes.append(TimedNote(sing, 2500, root, .target))
            return Timeline(notes: notes, lengthMs: sing + 2500 + tailMs, singStartMs: sing)
        case .breath, .balance:
            return Timeline(notes: [], lengthMs: 0, singStartMs: 0)
        case .pattern:
            break
        }

        let tune = Self.melody(ex, root: root)
        var lines: [Line] = []
        if let harmony = ex.harmony {
            lines.append(Line(notes: tune, gain: 1, target: false))
            lines.append(Line(notes: Harmony.voice(tune, key: key, mode: harmony, range: range), gain: 1, target: true))
        } else if let backing = ex.backing {
            let plan = Backing.arrange(tune, key: key, style: backing, lead: lead ?? VoiceType.classify(range.lowerBound, range.upperBound), singer: range, voices: ex.backingVoices)
            lines.append(Line(notes: plan.lead, gain: 1, target: false))
            let mine = min(max(ex.backingPart, 0), max(plan.parts.count - 1, 0))
            for (i, part) in plan.parts.enumerated() {
                lines.append(Line(notes: part.notes, gain: dbToGain(part.gainDb), target: i == mine))
            }
        } else {
            lines.append(Line(notes: tune, gain: 1, target: true))
        }
        var beatsTotal: Float = 0
        for i in 0..<ex.pattern.count { beatsTotal += (ex.beats != nil && i < ex.beats!.count) ? ex.beats![i] : 1 }
        let patternMs = beatsTotal * beatMs
        let lastEnd = lines.map { $0.notes.map { $0.endMs }.max() ?? 0 }.max() ?? 0
        let contentMs = max(patternMs, Float(lastEnd))
        let sing = Float(leadInMs) + contentMs + 2 * beatMs
        let singOnly = lines.count == 1
        for line in lines {
            for n in line.notes {
                notes.append(TimedNote(leadInMs + n.startMs, n.durMs, n.midi, .listen, gain: line.gain))
                if !singOnly || line.target {
                    notes.append(TimedNote(roundInt(sing) + n.startMs, n.durMs, n.midi, line.target ? .target : .accomp, gain: line.gain))
                }
            }
        }
        notes.sort { $0.startMs < $1.startMs }
        return Timeline(notes: notes, lengthMs: roundInt(sing + contentMs) + tailMs, singStartMs: roundInt(sing))
    }

    /// Lowest and highest semitone offsets an exercise reaches (including parallel second voices).
    public static func span(_ ex: Exercise) -> ClosedRange<Int> {
        let offsets = ex.pattern.compactMap { $0 }
        var lo = offsets.min() ?? 0
        var hi = offsets.max() ?? 0
        if let h = ex.harmony, h.parallel {
            let shift = h.octave != 0 ? (h.steps > 0 ? -9 : 9) : (h.steps > 0 ? 4 : -4)
            if shift > 0 { hi += shift } else { lo += shift }
        }
        return lo...hi
    }
}

/// Small deterministic random generator (SplitMix64) for reproducible exercises and tests.
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Sequence of roots for an exercise: up by `rootStep` and back down, inside the voice range.
public enum ExercisePlan {
    public static func roots(_ ex: Exercise, low: Int, high: Int, maxReps: Int = 16, seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) -> [Int] {
        let span = ExerciseTimeline.span(ex)
        if ex.kind == .echo {
            var rnd = SeededRandom(seed: seed)
            let lo = low + 1
            let hi = max(lo, high - 1)
            var last = -1
            var out: [Int] = []
            for _ in 0..<10 {
                var r: Int
                repeat {
                    r = Int.random(in: lo...hi, using: &rnd)
                } while r == last && hi > lo
                last = r
                out.append(r)
            }
            return out
        }
        let minRoot = low - span.lowerBound
        let maxRoot = high - span.upperBound
        var first = minRoot + 2
        var top = maxRoot - 1
        if first > top {
            first = (minRoot + maxRoot) / 2
            top = first
        }
        var up: [Int] = []
        var r = first
        while r <= top && up.count < maxReps / 2 + 1 {
            up.append(r)
            r += ex.rootStep
        }
        let down = Array(up.dropLast().reversed())
        return Array((up + down).prefix(maxReps))
    }
}

/// Scores sung pitch against the TARGET notes of a timeline.
/// A frame is a hit when it is within `toleranceCents` of the target (octave errors forgiven).
public final class Scorer {
    private let targets: [TimedNote]
    private let toleranceCents: Float
    private var hits: [Int]
    private var totals: [Int]
    private var cursor = 0

    public init(_ targets: [TimedNote], toleranceCents: Float = 50) {
        self.targets = targets
        self.toleranceCents = toleranceCents
        hits = [Int](repeating: 0, count: targets.count)
        totals = [Int](repeating: 0, count: targets.count)
    }

    public func reset() {
        for i in 0..<hits.count { hits[i] = 0; totals[i] = 0 }
        cursor = 0
    }

    /// Adds one analysis frame. `timeMs` is timeline time; `midi` is NaN when silent.
    public func add(_ timeMs: Float, _ midi: Float) {
        if targets.isEmpty { return }
        while cursor > 0 && Float(targets[cursor].startMs) > timeMs { cursor -= 1 }
        while cursor < targets.count - 1 && Float(targets[cursor].endMs) < timeMs { cursor += 1 }
        let n = targets[cursor]
        let from = Float(n.startMs + min(150, n.durMs / 4))
        let to = Float(n.endMs - min(60, n.durMs / 8))
        if timeMs < from || timeMs > to { return }
        totals[cursor] += 1
        if !midi.isNaN && abs(Pitch.foldedCents(midi, n.midi)) <= toleranceCents { hits[cursor] += 1 }
    }

    /// Accuracy 0...1 of note `i`, or -1 if it has not been evaluated yet.
    public func noteAccuracy(_ i: Int) -> Float {
        guard i >= 0 && i < totals.count, totals[i] > 0 else { return -1 }
        return Float(hits[i]) / Float(totals[i])
    }

    /// Average accuracy over the notes evaluated so far, or -1.
    public func total() -> Float {
        var sum: Float = 0
        var n = 0
        for i in 0..<targets.count where totals[i] > 0 {
            sum += Float(hits[i]) / Float(totals[i])
            n += 1
        }
        return n == 0 ? -1 : sum / Float(n)
    }

    /// Fraction of all evaluated frames that were hits (weights long notes more), or -1.
    public func frameAccuracy() -> Float {
        let t = totals.reduce(0, +)
        return t == 0 ? -1 : Float(hits.reduce(0, +)) / Float(t)
    }
}

/// Turns the smoothed pitch stream into the current note with hysteresis and a list of recent notes.
public final class NoteFollower {
    public private(set) var note = -1
    public private(set) var cents: Float = 0
    public private(set) var version = 0
    private let historySize: Int
    private var lastVoicedMs: Double = 0
    private var candidate = -1
    private var candidateSinceMs: Double = 0
    private var committed = -1
    private var recent: [Int] = []

    public init(historySize: Int = 10) { self.historySize = historySize }

    public func update(_ midi: Float, nowMs: Double) {
        if midi.isNaN {
            if note >= 0 && nowMs - lastVoicedMs > 250 {
                note = -1
                committed = -1
                candidate = -1
            }
            return
        }
        lastVoicedMs = nowMs
        let nearest = roundInt(midi)
        if note < 0 || (nearest != note && abs(midi - Float(note)) > 0.65) { note = nearest }
        cents = min(max((midi - Float(note)) * 100, -50), 50)
        if note != candidate {
            candidate = note
            candidateSinceMs = nowMs
        } else if note != committed && nowMs - candidateSinceMs >= 140 {
            committed = note
            recent.append(note)
            if recent.count > historySize { recent.removeFirst() }
            version += 1
        }
    }

    public var recentNotes: [Int] { recent }

    public func clear() {
        recent.removeAll()
        note = -1
        committed = -1
        candidate = -1
        version += 1
    }
}
