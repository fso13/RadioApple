import SwiftUI

/// Monochrome editorial palette: white paper, black ink, hairlines.
///
/// The design borrows the language of print: one accent (ink), no decorative
/// colours, colour only where content provides it (station artwork).
struct AppPalette {
    let isDark: Bool

    let window: Color
    let surface: Color
    let surfaceRaised: Color
    let surfaceHover: Color
    let surfaceActive: Color

    let separator: Color
    let separatorStrong: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    /// Active text / marks.
    let accent: Color
    /// Filled controls (buttons, play circle).
    let accentFill: Color
    /// Subtle wash for selected rows.
    let accentSoft: Color
    /// Content colour on top of `accentFill`.
    let onAccent: Color

    /// Reserved for live/error signals.
    let red: Color
    let green: Color

    let shadow: Color
}

extension AppPalette {
    static let light = AppPalette(
        isDark: false,
        window: Color(argb: 0xFFF2F2F2),
        surface: Color(argb: 0xFFFFFFFF),
        surfaceRaised: Color(argb: 0xFFFAFAFA),
        surfaceHover: Color(argb: 0xFFF6F6F6),
        surfaceActive: Color(argb: 0xFFEDEDED),
        separator: Color(argb: 0xFFE8E8E8),
        separatorStrong: Color(argb: 0xFFD9D9D9),
        textPrimary: Color(argb: 0xFF111111),
        textSecondary: Color(argb: 0xFF6B6B6B),
        textTertiary: Color(argb: 0xFFA6A6A6),
        accent: Color(argb: 0xFF111111),
        accentFill: Color(argb: 0xFF111111),
        accentSoft: Color(argb: 0xFFF1F1F1),
        onAccent: Color(argb: 0xFFFFFFFF),
        red: Color(argb: 0xFFD64545),
        green: Color(argb: 0xFF2E7D32),
        shadow: Color.black.opacity(0.10)
    )

    static let dark = AppPalette(
        isDark: true,
        window: Color(argb: 0xFF000000),
        surface: Color(argb: 0xFF0D0D0E),
        surfaceRaised: Color(argb: 0xFF141416),
        surfaceHover: Color(argb: 0xFF1A1A1D),
        surfaceActive: Color(argb: 0xFF232327),
        separator: Color(argb: 0xFF26262A),
        separatorStrong: Color(argb: 0xFF3A3A40),
        textPrimary: Color(argb: 0xFFF5F5F5),
        textSecondary: Color(argb: 0xFF9C9CA1),
        textTertiary: Color(argb: 0xFF63636A),
        accent: Color(argb: 0xFFFFFFFF),
        accentFill: Color(argb: 0xFFFFFFFF),
        accentSoft: Color(argb: 0xFF1C1C20),
        onAccent: Color(argb: 0xFF0D0D0E),
        red: Color(argb: 0xFFFF6B6B),
        green: Color(argb: 0xFF58D68D),
        shadow: Color.black.opacity(0.55)
    )

    static func resolved(for scheme: ColorScheme) -> AppPalette {
        scheme == .light ? .light : .dark
    }
}

extension Color {
    init(argb: UInt32) {
        let alpha = Double((argb >> 24) & 0xFF) / 255
        let red = Double((argb >> 16) & 0xFF) / 255
        let green = Double((argb >> 8) & 0xFF) / 255
        let blue = Double(argb & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = AppPalette.light
}

extension EnvironmentValues {
    var palette: AppPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
