import AppKit

/// Keyboard handling for the panel, ported from the Flutter shortcuts:
/// Esc hides (or leaves search), Space toggles, ↑/↓ move the selection,
/// Enter plays, 1–9 jump to a station, ⌘F focuses search, ⌘N adds a station.
final class KeyboardRouter {
    weak var panel: NSWindow?

    var onEscape: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onPlaySelected: (() -> Void)?
    var onPlayIndex: ((Int) -> Void)?
    var onFocusSearch: (() -> Void)?
    var onNewStation: (() -> Void)?
    var onResignSearch: (() -> Void)?

    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel,
                  panel.isVisible,
                  event.window === panel
            else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { uninstall() }

    private var isEditingText: Bool {
        panel?.firstResponder is NSTextView
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if flags.contains(.command) {
            switch characters {
            case "f":
                onFocusSearch?()
                return true
            case "n":
                onNewStation?()
                return true
            default:
                return false
            }
        }

        switch event.keyCode {
        case 53: // Escape
            if isEditingText {
                onResignSearch?()
            } else {
                onEscape?()
            }
            return true
        default:
            break
        }

        // Everything below must not steal typing inside the search/editor fields.
        guard !isEditingText, flags.isEmpty || flags == .function else { return false }

        switch event.keyCode {
        case 49: // Space
            onPlayPause?()
            return true
        case 125: // Arrow down
            onMoveSelection?(1)
            return true
        case 126: // Arrow up
            onMoveSelection?(-1)
            return true
        case 36, 76: // Return / keypad Enter
            onPlaySelected?()
            return true
        default:
            break
        }

        if let characters, characters.count == 1, let digit = Int(characters), (1...9).contains(digit) {
            onPlayIndex?(digit - 1)
            return true
        }
        return false
    }
}
