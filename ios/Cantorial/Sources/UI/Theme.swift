import SwiftUI
import UIKit

/// Warm palette: dark roasted brown or cream paper, amber accent, sand and terracotta tones.
/// The same colours as the Android app, following the system light/dark setting.
enum Palette {
    private static func dynamic(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let bg = dynamic(0x140F0C, 0xFCF6EE)
    static let surface = dynamic(0x1E1713, 0xF5EBDD)
    static let surface2 = dynamic(0x2A201A, 0xEDDFCC)
    static let line = dynamic(0x3A2D24, 0xE3D2BC)
    static let text = dynamic(0xF8EDE2, 0x2B1E15)
    static let muted = dynamic(0xB09A87, 0x7D6656)
    static let faint = dynamic(0x6A574A, 0xC2AD98)
    /// Amber: what you sing, primary actions, good pitch.
    static let accent = dynamic(0xF5A33B, 0xE08A12)
    static let onAccent = dynamic(0x2B1600, 0x2B1600)
    /// Sand: the lead melody (regente).
    static let melody = dynamic(0xD8BFA6, 0x9E7B5D)
    /// Rose: other harmony / backing parts.
    static let rose = dynamic(0xE88A8F, 0xC4525E)
    static let warn = dynamic(0xEE6A35, 0xD5612A)
    static let bad = dynamic(0xD8434B, 0xB8302F)
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

enum Typo {
    static let display = Font.system(size: 104, weight: .light)
    static let title = Font.system(size: 28, weight: .semibold)
    static let heading = Font.system(size: 18, weight: .semibold)
    static let body = Font.system(size: 16)
    static let label = Font.system(size: 14, weight: .medium)
    static let small = Font.system(size: 13)
    static let caps = Font.system(size: 12, weight: .semibold)
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
