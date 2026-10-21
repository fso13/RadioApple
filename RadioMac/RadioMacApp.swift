import AppKit

/// Process entry point. The app is an accessory (menu-bar) agent, so it owns no
/// main window and no Dock icon; AppKit is started by hand instead of a nib.
@main
@MainActor
enum RadioMacApp {
    static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
