import AppKit
import Combine
import SwiftUI

/// Menu-bar item: left click toggles the panel, right click shows the action menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let environment: AppEnvironment
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    var onToggleWindow: (() -> Void)?
    var onShowWindow: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onQuit: (() -> Void)?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        configureButton()
        configurePopover()
        observePlayer()
        refreshTooltip()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(named: "TrayIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            button.image = NSImage(
                systemSymbolName: "dot.radiowaves.left.and.right",
                accessibilityDescription: "RadioMac"
            )
        }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "RadioMac"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MiniPlayerView(
                player: environment.player,
                library: environment.library,
                theme: environment.theme,
                onOpenWindow: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.onShowWindow?()
                }
            )
        )
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func observePlayer() {
        let player = environment.player
        let publisher = Publishers.MergeMany(
            player.$status.map { _ in () }.eraseToAnyPublisher(),
            player.$nowPlaying.map { _ in () }.eraseToAnyPublisher(),
            player.$station.map { _ in () }.eraseToAnyPublisher()
        )
        publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshTooltip() }
            .store(in: &cancellables)
    }

    // MARK: - Clicks

    @objc private func handleClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentMenu()
        } else {
            togglePopover()
        }
    }

    private func presentMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let player = environment.player
        if let station = player.station, !station.name.isEmpty {
            menu.addItem(disabledItem(station.name))
        }
        if let track = player.nowPlaying?.trayLine, !track.isEmpty {
            menu.addItem(disabledItem(truncated(track, limit: 48)))
        }
        if menu.items.isEmpty == false { menu.addItem(.separator()) }

        let toggle = NSMenuItem(
            title: player.isPlaying ? "Пауза" : "Играть",
            action: #selector(playPause),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let stop = NSMenuItem(title: "Стоп", action: #selector(stopPlayback), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Показать", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let updates = NSMenuItem(title: "Проверить обновления…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let settings = NSMenuItem(title: "Настройки", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Завершить", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit - 1)) + "…"
    }

    private func refreshTooltip() {
        guard let button = statusItem.button else { return }
        let player = environment.player

        var parts: [String] = []
        if let name = player.station?.name, !name.isEmpty { parts.append(name) }
        if let track = player.nowPlaying?.trayLine, !track.isEmpty { parts.append(track) }
        let body = parts.joined(separator: " · ")

        var tip = body.isEmpty ? "RadioMac" : (player.isPlaying ? "▶ \(body)" : body)
        if tip.count > 90 { tip = String(tip.prefix(89)) + "…" }
        button.toolTip = tip
    }

    // MARK: - Actions

    @objc private func playPause() { onPlayPause?() }
    @objc private func stopPlayback() { onStop?() }
    @objc private func showWindow() { onShowWindow?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func quitApp() { onQuit?() }
}
