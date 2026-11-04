import Foundation
import CantorialCore

/// Deterministic Gaussian noise (SplitMix64 + Box-Muller), the same as the scratch Kotlin
/// reference run, so the thresholds here match what the Android tests measure.
struct TestRandom {
    private var state: UInt64

    init(_ seed: Int64) { state = UInt64(bitPattern: seed) }

    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private mutating func uniform() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }

    mutating func nextGaussian() -> Double {
        let u1 = max(uniform(), 1e-12)
        let u2 = uniform()
        return (-2.0 * log(u1)).squareRoot() * cos(2.0 * Double.pi * u2)
    }
}

func line(_ midi: [Int], dur: Int = 450, gap: Int = 50) -> [NoteEvent] {
    midi.enumerated().map { NoteEvent($0.offset * (dur + gap), dur, $0.element) }
}

/// "Ode à Alegria" in C, around C4.
let ode = line([64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62])
