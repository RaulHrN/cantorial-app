import Foundation

/// Floor modulo (always 0..<m for positive m), like Math.floorMod.
@inline(__always) public func floorMod(_ a: Int, _ m: Int) -> Int {
    let r = a % m
    return r < 0 ? r + m : r
}

/// Floor division, like Math.floorDiv.
@inline(__always) public func floorDiv(_ a: Int, _ m: Int) -> Int {
    let q = a / m
    return (a % m != 0 && (a < 0) != (m < 0)) ? q - 1 : q
}

public enum Pitch {
    public static func hzToMidi(_ hz: Float, a4: Float = 440) -> Float {
        Float(69.0 + 12.0 * log2(Double(hz) / Double(a4)))
    }

    public static func midiToHz(_ midi: Float, a4: Float = 440) -> Float {
        Float(Double(a4) * pow(2.0, (Double(midi) - 69.0) / 12.0))
    }

    public static func pitchClass(_ midi: Int) -> Int { floorMod(midi, 12) }

    /// Distance in cents between `midi` and `target`, folded to the nearest octave (-600...600].
    public static func foldedCents(_ midi: Float, _ target: Int) -> Float {
        var d = (midi - Float(target)) * 100
        d = d.truncatingRemainder(dividingBy: 1200)
        if d > 600 { d -= 1200 }
        if d <= -600 { d += 1200 }
        return d
    }
}

public enum Naming: String, Codable, CaseIterable {
    case solfege = "SOLFEGE"
    case letters = "LETTERS"
}

public enum NoteNames {
    private static let solfegeSharp = ["Dó", "Dó#", "Ré", "Ré#", "Mi", "Fá", "Fá#", "Sol", "Sol#", "Lá", "Lá#", "Si"]
    private static let solfegeFlat = ["Dó", "Réb", "Ré", "Mib", "Mi", "Fá", "Solb", "Sol", "Láb", "Lá", "Sib", "Si"]
    private static let letterSharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let letterFlat = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let tables = [solfegeSharp, solfegeFlat, letterSharp, letterFlat]
    // Full names ("Lá4") cached for every MIDI note so the UI never builds strings per frame.
    private static let full: [[String]] = (0..<4).map { t in (0..<128).map { m in tables[t][m % 12] + String(m / 12 - 1) } }

    private static func table(_ naming: Naming, _ flats: Bool) -> Int {
        (naming == .solfege ? 0 : 2) + (flats ? 1 : 0)
    }

    public static func pitchClass(_ pc: Int, _ naming: Naming, flats: Bool = false) -> String {
        tables[table(naming, flats)][floorMod(pc, 12)]
    }

    public static func name(_ midi: Int, _ naming: Naming, flats: Bool = false) -> String {
        pitchClass(midi, naming, flats: flats)
    }

    public static func octave(_ midi: Int) -> Int { floorDiv(midi, 12) - 1 }

    public static func full(_ midi: Int, _ naming: Naming, flats: Bool = false) -> String {
        if midi < 0 || midi > 127 { return pitchClass(midi, naming, flats: flats) + String(octave(midi)) }
        return full[table(naming, flats)][midi]
    }
}

/// A tonality: tonic pitch class (0 = C) and mode. Minor uses the natural minor scale.
public struct Key: Codable, Hashable {
    public var tonic: Int
    public var minor: Bool

    public init(_ tonic: Int, _ minor: Bool) {
        self.tonic = tonic
        self.minor = minor
    }

    public static let majorScale = [0, 2, 4, 5, 7, 9, 11]
    public static let minorScale = [0, 2, 3, 5, 7, 8, 10]
    private static let majorFlats: Set<Int> = [5, 10, 3, 8, 1]
    private static let minorFlats: Set<Int> = [2, 7, 0, 5, 10, 3]

    public var scale: [Int] { minor ? Key.minorScale : Key.majorScale }

    public var prefersFlats: Bool {
        minor ? Key.minorFlats.contains(tonic) : Key.majorFlats.contains(tonic)
    }

    /// Scale degree (0...6) of a pitch class, or -1 if it is chromatic in this key.
    public func degreeOf(_ pc: Int) -> Int {
        scale.firstIndex(of: floorMod(pc - tonic, 12)) ?? -1
    }

    public func label(_ naming: Naming) -> String {
        NoteNames.pitchClass(tonic, naming, flats: prefersFlats) + (minor ? " menor" : " maior")
    }
}

public enum VoiceType: String, Codable, CaseIterable, Identifiable {
    case bass = "BASS"
    case baritone = "BARITONE"
    case tenor = "TENOR"
    case contralto = "CONTRALTO"
    case mezzo = "MEZZO"
    case soprano = "SOPRANO"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bass: return "Baixo"
        case .baritone: return "Barítono"
        case .tenor: return "Tenor"
        case .contralto: return "Contralto"
        case .mezzo: return "Mezzo-soprano"
        case .soprano: return "Soprano"
        }
    }

    public var low: Int {
        switch self {
        case .bass: return 40
        case .baritone: return 45
        case .tenor: return 48
        case .contralto: return 53
        case .mezzo: return 57
        case .soprano: return 60
        }
    }

    public var high: Int { low + 24 }

    public var center: Int { (low + high) / 2 }

    /// Typical comfortable range for parts written for this voice.
    public var range: ClosedRange<Int> { (low + 2)...(high - 2) }

    public var female: Bool { self == .contralto || self == .mezzo || self == .soprano }

    /// Picks the type whose typical range is closest to the measured one.
    public static func classify(_ low: Int, _ high: Int) -> VoiceType {
        allCases.min { a, b in score(a, low, high) < score(b, low, high) }!
    }

    private static func score(_ t: VoiceType, _ low: Int, _ high: Int) -> Float {
        Float(abs(t.low - low) + abs(t.high - high)) + 0.5 * Float(abs((t.low + t.high) - (low + high)))
    }
}
