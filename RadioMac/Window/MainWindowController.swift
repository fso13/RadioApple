import AppKit
import Combine
import SwiftUI

/// Services and UI state shared by the status item and the panel.
final class AppEnvironment {
    let settings: AppSettings
    let theme: ThemeService
    let library: StationLibrary
    let equalizer: EqualizerService
    let player: RadioPlayerService
    let toasts = ToastCenter()
    let router = WindowRouter()
    let mainModel: MainViewModel

    init() {
        PreferencesMigrator.migrateIfNeeded()
        settings = AppSettings()
        theme = ThemeService()
        library = StationLibrary()
        equalizer = EqualizerService()
        player = RadioPlayerService(settings: settings, library: library, equalizer: equalizer)
        mainModel = MainViewModel(library: library)

        library.load()
        player.start()
    }
}

/// Borderless panel that can still take keyboard focus (needed for search and
/// the single-key shortcuts).
final class RadioPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the frameless 420×680 panel and the show/hide animation.
final class MainWindowController: NSWindowController {
    static let panelSize = NSSize(width: 780, height: 660)

    private let panel: RadioPanel
    private let environment: AppEnvironment
    private let keyboard = KeyboardRouter()
    private var cancellables: Set<AnyCancellable> = []
    private var isHiding = false
    private var hasPositioned = false
    /// Guards the asynchronous hide animation against an immediate re-show.
    private var visibilityGeneration = 0

    init(environment: AppEnvironment) {
        self.environment = environment
        panel = RadioPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        configurePanel()
        buildContent()
        wireKeyboard()
        observeTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = Self.panelSize
        panel.maxSize = Self.panelSize
        panel.setContentSize(Self.panelSize)
    }

    private func buildContent() {
        let root = RootView(
            router: environment.router,
            model: environment.mainModel,
            settings: environment.settings,
            theme: environment.theme,
            library: environment.library,
            player: environment.player,
            equalizer: environment.equalizer,
            toasts: environment.toasts,
            onClose: { [weak self] in self?.hide() },
            onQuit: { NSApp.terminate(nil) }
        )

        // A plain container keeps AppKit from resizing the panel to the hosting
        // view's fitting size; the panel must stay exactly 420×680.
        let container = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
        container.wantsLayer = true

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        panel.setContentSize(Self.panelSize)
    }

    private func wireKeyboard() {
        keyboard.panel = panel
        keyboard.install()

        let environment = self.environment
        keyboard.onEscape = { [weak self] in self?.hide() }
        keyboard.onPlayPause = { environment.player.togglePlayPause() }
        keyboard.onMoveSelection = { environment.mainModel.moveSelection($0) }
        keyboard.onPlaySelected = { environment.mainModel.playSelected(using: environment.player) }
        keyboard.onPlayIndex = { environment.mainModel.playVisible(at: $0, using: environment.player) }
        keyboard.onFocusSearch = { [weak self] in
            guard let self else { return }
            if self.environment.router.route != .main {
                self.environment.router.route = .main
            }
            self.environment.mainModel.focusSearch()
        }
        keyboard.onNewStation = { [weak self] in
            guard let self else { return }
            if self.environment.router.route != .main {
                self.environment.router.route = .main
            }
            self.environment.mainModel.newStation()
        }
        keyboard.onResignSearch = { environment.mainModel.resignSearch() }
    }

    private func observeTheme() {
        panel.appearance = environment.theme.preference.appearance
        environment.theme.$preference
            .receive(on: RunLoop.main)
            .sink { [weak self] preference in
                self?.panel.appearance = preference.appearance
            }
            .store(in: &cancellables)
    }

    // MARK: - Visibility

    var isVisible: Bool { panel.isVisible && !isHiding }

    func show(route: WindowRoute) {
        visibilityGeneration += 1
        isHiding = false
        environment.router.route = route
        centerIfNeeded()

        NSApp.activate(ignoringOtherApps: true)

        if panel.isVisible {
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
            return
        }

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func showMainWindow() {
        show(route: .main)
    }

    func showSettings() {
        show(route: .settings)
    }

    func hide() {
        guard panel.isVisible, !isHiding else { return }
        isHiding = true
        visibilityGeneration += 1
        let generation = visibilityGeneration

        environment.router.sheet = nil
        environment.mainModel.editor = nil
        panel.makeFirstResponder(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // A re-show during the fade-out bumps the generation and keeps the panel.
            guard let self, self.visibilityGeneration == generation else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.isHiding = false
            self.environment.router.route = .main
            self.environment.mainModel.resetAfterHide()
        }
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            showMainWindow()
        }
    }

#if DEBUG
    func snapshotPanel(to url: URL) {
        guard let view = panel.contentView else { return }
        writeSnapshot(of: view, to: url)
    }

    func snapshotKeyWindow(to url: URL) {
        if let key = NSApp.keyWindow, key !== panel, let view = key.contentView {
            writeSnapshot(of: view, to: url)
        } else {
            snapshotPanel(to: url)
        }
    }

    private func writeSnapshot(of view: NSView, to url: URL) {
        view.window?.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Render at 2× regardless of the window's backing scale.
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    func snapshotSheet(to url: URL) {
        let sheet = NSApp.windows.first { $0.isVisible && $0.sheetParent != nil }
        guard let view = sheet?.contentView else {
            snapshotKeyWindow(to: url)
            return
        }
        writeSnapshot(of: view, to: url)
    }
#endif

    private func centerIfNeeded() {
        guard !hasPositioned else { return }
        hasPositioned = true
        panel.center()

        if let screen = panel.screen ?? NSScreen.main {
            var frame = panel.frame
            frame.origin.y += 40
            let visible = screen.visibleFrame
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            panel.setFrame(frame, display: false)
        }
    }
}
