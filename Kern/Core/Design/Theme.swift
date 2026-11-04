import SwiftUI
import UIKit

/// Zentrale Design-Tokens. Bewusst reduziert: flache Flächen, keine Schatten,
/// keine Farbverläufe. Liquid Glass wird ausschliesslich für die Steuerungs- und
/// Navigationsebene verwendet (Tab-Bar, Toolbars, schwebende Aktionen), nicht für Inhalte.
enum Theme {
    // MARK: Farben

    /// Markenfarbe – ein ruhiges, tiefes Grün.
    static let accent = Color(light: 0x1E7F5C, dark: 0x4CC492)

    static let energy = Color(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let protein = Color(light: 0x3767D6, dark: 0x7AA2FF)
    static let carbs = Color(light: 0xC98A1B, dark: 0xF0B557)
    static let fat = Color(light: 0xB8507A, dark: 0xE88AAE)
    static let fiber = Color(light: 0x5E8C31, dark: 0x9BCB6A)
    static let water = Color(light: 0x1F8FC7, dark: 0x5CC2EE)
    static let training = Color(light: 0xD45A2E, dark: 0xFF8A5C)
    static let weight = Color(light: 0x5A5AD6, dark: 0x9C9CFF)
    static let supplement = Color(light: 0x2E8C8C, dark: 0x5CCFCF)
    static let cycle = Color(light: 0xA2509E, dark: 0xD68CD2)
    static let warning = Color(light: 0xC2410C, dark: 0xFB923C)
    static let positive = Color(light: 0x15803D, dark: 0x4ADE80)

    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceRaised = Color(uiColor: .tertiarySystemGroupedBackground)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let fillStrong = Color(uiColor: .secondarySystemFill)
    static let separator = Color(uiColor: .separator)

    // MARK: Masse

    enum Radius {
        static let card: CGFloat = 22
        static let control: CGFloat = 14
        static let small: CGFloat = 10
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
    }

    /// Standard-Innenabstand für Bildschirme.
    static let screenPadding: CGFloat = 16
}

// MARK: - Typografie

extension Font {
    /// Grosse Kennzahl, z. B. verbleibende Kalorien.
    static let metricLarge = Font.system(size: 44, weight: .semibold, design: .rounded)
    static let metricMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let metricSmall = Font.system(.title3, design: .rounded).weight(.semibold)
    static let cardTitle = Font.subheadline.weight(.semibold)
    static let caption2Strong = Font.caption2.weight(.semibold)
}

// MARK: - Farb-Helfer

extension Color {
    /// Dynamische Farbe für hellen und dunklen Modus.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
