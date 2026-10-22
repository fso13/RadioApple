import Carbon.HIToolbox
import Foundation

enum HotKeyAction: String, CaseIterable, Identifiable, Sendable {
    case playPause
    case nextStation

    var id: String { rawValue }
    var title: String {
        switch self {
        case .playPause: return "Играть / пауза"
        case .nextStation: return "Следующая станция"
        }
    }
}

enum HotKeyKey: UInt32, CaseIterable, Identifiable, Sendable, Codable {
    case p = 35
    case n = 45
    case space = 49
    case rightArrow = 124
    case leftArrow = 123
    case f8 = 100
    case f9 = 101

    var id: UInt32 { rawValue }
    var title: String {
        switch self {
        case .p: return "P"
        case .n: return "N"
        case .space: return "Space"
        case .rightArrow: return "→"
        case .leftArrow: return "←"
        case .f8: return "F8"
        case .f9: return "F9"
        }
    }
}

struct HotKeyCombo: Codable, Equatable, Sendable {
    var key: HotKeyKey
    var modifiers: UInt32

    static let defaultPlayPause = HotKeyCombo(
        key: .p,
        modifiers: UInt32(optionKey | cmdKey)
    )
    static let defaultNext = HotKeyCombo(
        key: .rightArrow,
        modifiers: UInt32(optionKey | cmdKey)
    )

    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + key.title
    }

    var systemConflictReason: String? {
        let command = UInt32(cmdKey)
        let option = UInt32(optionKey)
        let control = UInt32(controlKey)
        let shift = UInt32(shiftKey)

        switch (key, modifiers) {
        case (.space, command):
            return "⌘Space занят Spotlight"
        case (.n, command), (.p, command), (.f8, command), (.f9, command):
            return "Сочетание пересекается с системным меню"
        case (.space, command | control):
            return "⌃⌘Space занят Character Viewer"
        case (.rightArrow, control), (.leftArrow, control),
             (.rightArrow, control | option), (.leftArrow, control | option):
            return "Сочетание занято Mission Control"
        case (.p, command | option), (.n, command | option):
            return nil
        case (_, command):
            return "Не используйте ⌘ без ⌥: конфликт с системным меню"
        case (_, command | shift):
            return "⌘⇧ зарезервировано системой для скриншотов"
        default:
            return nil
        }
    }

    static func decode(_ raw: String?, fallback: HotKeyCombo) -> HotKeyCombo {
        guard let raw, let data = raw.data(using: .utf8),
              let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data)
        else { return fallback }
        return combo
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
