import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var windowController: MainWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
#if DEBUG
        DebugLog.write("launch: args=\(ProcessInfo.processInfo.arguments)")
#endif

        let environment = AppEnvironment()
        self.environment = environment

        let windowController = MainWindowController(environment: environment)
        self.windowController = windowController
        let statusItem = StatusItemController(environment: environment)
        statusItem.onToggleWindow = { [weak windowController] in windowController?.toggle() }
        statusItem.onShowWindow = { [weak windowController] in windowController?.showMainWindow() }
        statusItem.onOpenSettings = { [weak windowController] in windowController?.showSettings() }
        statusItem.onPlayPause = { [weak environment] in
            guard let environment else { return }
            if environment.player.station == nil,
               let first = environment.library.stations.first {
                environment.player.play(first)
                return
            }
            environment.player.togglePlayPause()
        }
        statusItem.onStop = { [weak environment] in environment?.player.stop() }
        statusItem.onQuit = { NSApp.terminate(nil) }
        statusItemController = statusItem

#if DEBUG
        if DebugHarness.handle(
            arguments: ProcessInfo.processInfo.arguments,
            environment: environment,
            window: windowController
        ) {
            return
        }
#endif

        if ProcessInfo.processInfo.arguments.contains("-showWindow") {
            windowController.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.diagnostics.markCleanExit()
        environment?.player.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// LSUIElement apps have no visible menu bar, but a main menu is still needed
    /// for the standard editing key equivalents (⌘C / ⌘V / ⌘A in text fields).
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Завершить RadioMac",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
