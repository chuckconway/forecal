import AppKit
import SwiftUI

/// The panel's palette. System secondary colors and low-opacity greys are tuned
/// for dark, translucent surfaces and wash out to grey in light mode, so every
/// color here is set explicitly for each appearance, on an opaque background.
enum Theme {
    static let background = Color(light: 0xFFFFFF, dark: 0x1E1E20)
    static let separator = Color(light: 0xDCDFE5, dark: 0x3A3A3E)
    /// Bottom edge of the month grid, firmer than other separators.
    static let gridEdge = Color(light: 0xC2C8D2, dark: 0x5C5C63)
    /// Kept faint: it should separate the grid from the list without drawing the eye.
    static let gridShadow = Color(light: 0x8A94A6, dark: 0x000000).opacity(0.16)

    static let text = Color(light: 0x111114, dark: 0xF5F5F7)
    static let textSecondary = Color(light: 0x4B4B52, dark: 0xB4B4BA)
    static let textTertiary = Color(light: 0x7A7A82, dark: 0x8A8A90)
    static let outOfMonth = Color(light: 0xA9ABB2, dark: 0x5E5E63)

    /// Day header bands in the agenda, and the selected week in the grid.
    static let band = Color(light: 0xEDF0F5, dark: 0x2C2C30)
    static let selectedDay = Color(light: 0xCFD5E0, dark: 0x48484E)

    /// Today's color: text that stays readable on white, a solid fill for the
    /// grid circle, and a soft band behind the agenda header.
    static var accent: Accent { accentOverride ?? Accent.saved }
    /// Snapshots set this to render each option without touching the saved choice.
    static var accentOverride: Accent?
    static var today: Color { accent.text }
    static var todayFill: Color { accent.fill }
    static var todayBand: Color { accent.band }

    static let rain = Color(light: 0x0A60C2, dark: 0x64B0FF)
    static let cloud = Color(light: 0x8A94A6, dark: 0xC7C7CC)
    static let sun = Color(light: 0xF29D00, dark: 0xFFD60A)
    static let snow = Color(light: 0x5AB4E0, dark: 0xA0DCFF)
    static let leave = Color(light: 0xA84B00, dark: 0xFFB340)
    static let leaveBand = Color(light: 0xFFEBD3, dark: 0x3D2C14)
}

/// The user's choice of color for today, matched in strength and lightness to
/// the red. Chosen in the gear menu.
enum Accent: String, CaseIterable, Identifiable {
    case red, blue, indigo

    static let storageKey = "todayColor"

    static var saved: Accent {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Accent.init(rawValue:)) ?? .red
    }

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var text: Color {
        switch self {
        case .red: Color(light: 0xD1281D, dark: 0xFF6961)
        case .blue: Color(light: 0x1F5BC8, dark: 0x6AA8FF)
        case .indigo: Color(light: 0x4F3FCF, dark: 0x9D8CFF)
        }
    }

    var fill: Color {
        switch self {
        case .red: Color(light: 0xE5372A, dark: 0xFF453A)
        case .blue: Color(light: 0x2F6FE4, dark: 0x3D8BFF)
        case .indigo: Color(light: 0x5E4FE0, dark: 0x7A68F5)
        }
    }

    var band: Color {
        switch self {
        case .red: Color(light: 0xFDE4E1, dark: 0x3B2224)
        case .blue: Color(light: 0xE1EAFB, dark: 0x1E2A3E)
        case .indigo: Color(light: 0xE8E5FC, dark: 0x27243F)
        }
    }
}

extension Color {
    /// A color that follows the view's appearance, from 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
