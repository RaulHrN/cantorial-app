import SwiftUI
import UIKit

/// Classical palette: parchment or dark olive ink, sage and deep olive greens, sand, ochre and
/// the terracotta red of the maple in the illustrations. The same colours as the Android app,
/// following the system light/dark setting.
enum Palette {
    private static func dynamic(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let bg = dynamic(0x1B1C16, 0xF2EADC)
    static let surface = dynamic(0x25261E, 0xE8DDCA)
    static let surface2 = dynamic(0x323327, 0xDCD0BA)
    static let line = dynamic(0x414234, 0xCDBFA6)
    static let text = dynamic(0xEFE6D6, 0x26271D)
    static let muted = dynamic(0xAAA28C, 0x6F6853)
    static let faint = dynamic(0x6C6857, 0xAA9F87)
    /// Sage green: what you sing, highlights, chords, good pitch.
    static let accent = dynamic(0xA9BC85, 0x58713B)
    static let onAccent = dynamic(0x1B2412, 0xF4ECDD)
    /// Deep olive: main buttons.
    static let primary = dynamic(0x5B6D47, 0x34422D)
    static let onPrimary = dynamic(0xF4ECDD, 0xF4ECDD)
    /// Sand: the lead melody (regente).
    static let melody = dynamic(0xD6C2A0, 0x8F7655)
    /// Mauve: other harmony / backing parts.
    static let rose = dynamic(0xB392B8, 0x84608A)
    static let warn = dynamic(0xDBA845, 0xB0751A)
    static let bad = dynamic(0xD9694A, 0xB2452B)
    /// Terracotta of the maple leaves in the illustrations.
    static let leaf = dynamic(0xC9573B, 0xB8452C)
    static let leafLight = dynamic(0xDD7450, 0xCB5B3C)
    static let rock = dynamic(0x2F3026, 0xCDBFA6)
    static let trunk = dynamic(0x55463A, 0x4A372B)
    static let sun = Color(UIColor { traits in
        UIColor(rgb: 0xD9916B).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.20 : 0.34)
    })
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Serif type throughout, like engraved sheet music.
enum Typo {
    static let display = Font.system(size: 104, weight: .regular, design: .serif)
    static let title = Font.system(size: 30, weight: .regular, design: .serif)
    static let heading = Font.system(size: 19, weight: .medium, design: .serif)
    static let body = Font.system(size: 16, design: .serif)
    static let label = Font.system(size: 15, weight: .medium, design: .serif)
    static let small = Font.system(size: 13.5, design: .serif)
    static let caps = Font.system(size: 12, weight: .semibold, design: .serif)
}

let screenPadding: CGFloat = 20

func formatTime(_ ms: Float) -> String {
    let total = max(0, Int(ms / 1000))
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// "1,5" style decimals for Portuguese text.
func decimal(_ v: Float, digits: Int = 1) -> String {
    String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
}
