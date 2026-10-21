import AppKit
import SwiftUI

/// Light/dark/system theme choice, persisted under the same key as the Flutter app.
@MainActor
final class ThemeService: ObservableObject {
    enum Preference: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "Как в системе"
            case .light: return "Светлая"
            case .dark: return "Тёмная"
            }
        }

        var detail: String {
            switch self {
            case .system: return "Автоматически переключать тему в зависимости от настроек системы"
            case .light: return "Всегда использовать светлую тему"
            case .dark: return "Всегда использовать тёмную тему"
            }
        }

        /// `nil` hands appearance control back to macOS.
        var appearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    private let defaults: UserDefaults
    @Published private(set) var preference: Preference

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: DefaultsKey.themePreference)
        preference = raw.flatMap(Preference.init(rawValue:)) ?? .system
    }

    func setPreference(_ value: Preference) {
        guard value != preference else { return }
        preference = value
        defaults.set(value.rawValue, forKey: DefaultsKey.themePreference)
    }
}

/// Root view: resolves the palette from the effective appearance and hands it
/// down through the environment so every subview can read `@Environment(\.palette)`.
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let palette = AppPalette.resolved(for: colorScheme)
        content()
            .environment(\.palette, palette)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
