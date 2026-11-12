import CantorialCore
import Foundation
import Observation

/// User preferences, saved in UserDefaults and observed by the screens.
@Observable
final class Prefs {
    static let shared = Prefs()

    private let store = UserDefaults.standard

    private var storedNaming: Naming
    private var storedA4: Float
    private var storedSensitivity: Float
    private(set) var rangeLow: Int
    private(set) var rangeHigh: Int
    private(set) var rangeMeasured: Bool
    private var storedLeadLevel: Float
    private var storedCifraSize: Float

    private init() {
        let d = UserDefaults.standard
        storedNaming = Naming(rawValue: d.string(forKey: "naming") ?? "") ?? .solfege
        storedA4 = d.object(forKey: "a4") != nil ? d.float(forKey: "a4") : 440
        storedSensitivity = d.object(forKey: "sensitivity") != nil ? d.float(forKey: "sensitivity") : 0.5
        rangeLow = d.object(forKey: "low") != nil ? d.integer(forKey: "low") : 48
        rangeHigh = d.object(forKey: "high") != nil ? d.integer(forKey: "high") : 67
        rangeMeasured = d.bool(forKey: "measured")
        storedLeadLevel = d.object(forKey: "leadLevel") != nil ? d.float(forKey: "leadLevel") : .nan
        storedCifraSize = d.object(forKey: "cifraSize") != nil ? d.float(forKey: "cifraSize") : 15
        applyToEngine()
    }

    var naming: Naming {
        get { storedNaming }
        set {
            storedNaming = newValue
            store.set(newValue.rawValue, forKey: "naming")
        }
    }

    var a4: Float {
        get { storedA4 }
        set {
            storedA4 = min(max(newValue, 415), 466)
            store.set(storedA4, forKey: "a4")
            applyToEngine()
        }
    }

    /// 0 = only loud sounds, 1 = picks up very soft singing.
    var sensitivity: Float {
        get { storedSensitivity }
        set {
            storedSensitivity = min(max(newValue, 0), 1)
            store.set(storedSensitivity, forKey: "sensitivity")
            applyToEngine()
        }
    }

    /// Microphone level (dB) of the user singing at lead-voice volume. Backing levels are shown
    /// relative to it. NaN until calibrated.
    var leadLevelDb: Float {
        get { storedLeadLevel }
        set {
            storedLeadLevel = newValue
            store.set(newValue, forKey: "leadLevel")
        }
    }

    /// Text size (points) of chord sheets.
    var cifraSize: Float {
        get { storedCifraSize }
        set {
            storedCifraSize = min(max(newValue, 11), 26)
            store.set(storedCifraSize, forKey: "cifraSize")
        }
    }

    var range: ClosedRange<Int> { rangeLow...rangeHigh }

    var voiceType: VoiceType { VoiceType.classify(rangeLow, rangeHigh) }

    func setRange(_ low: Int, _ high: Int, measured: Bool) {
        let lo = min(max(min(low, high - 5), 28), 90)
        let hi = min(max(max(high, lo + 5), lo + 5), 100)
        rangeLow = lo
        rangeHigh = hi
        rangeMeasured = measured
        store.set(lo, forKey: "low")
        store.set(hi, forKey: "high")
        store.set(measured, forKey: "measured")
    }

    private func applyToEngine() {
        MicEngine.shared.a4 = storedA4
        MicEngine.shared.gateDb = -38 - 24 * storedSensitivity
    }
}
