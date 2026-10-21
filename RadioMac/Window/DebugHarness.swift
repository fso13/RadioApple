#if DEBUG
import AppKit
import Combine
import Foundation

/// Developer utilities, compiled into Debug builds only.
///
/// * `-snapshot <name>` renders the panel and its sheets to PNGs and quits.
///   Files land in `<container tmp>/radio-debug.log`'s sibling folder `<name>`.
/// * `-playtest <file>` starts three streams (MP3, AAC, MP3) and records the
///   observed playback states next to the log.
///
/// Both write only inside the sandbox container, so they work without granting
/// the app access to the user's folders.
@MainActor
enum DebugHarness {
    static func handle(
        arguments: [String],
        environment: AppEnvironment,
        window: MainWindowController
    ) -> Bool {
        if let name = value(after: "-snapshot", in: arguments) {
            runSnapshots(directory: scratchDirectory(named: name), environment: environment, window: window)
            return true
        }
        if let name = value(after: "-playtest", in: arguments) {
            runPlaytest(output: scratchDirectory(named: "").appendingPathComponent(name), environment: environment)
            return true
        }
        return false
    }

    // MARK: - Snapshots

    private static func runSnapshots(
        directory: URL,
        environment: AppEnvironment,
        window: MainWindowController
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var delay: TimeInterval = 1.6
        func after(_ block: @escaping @MainActor () -> Void) {
            let wait = delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                block()
            }
            delay += 0.7
        }

        window.showMainWindow()
        environment.theme.setPreference(.light)
        environment.mainModel.clearSearch()
        environment.mainModel.setFilter(.all)

        after { window.snapshotPanel(to: directory.appendingPathComponent("01-main.png")) }
        after { environment.router.route = .settings }
        after { window.snapshotPanel(to: directory.appendingPathComponent("02-settings.png")) }
        after { environment.router.sheet = .equalizer }
        after { window.snapshotSheet(to: directory.appendingPathComponent("03-equalizer.png")) }
        after { environment.router.sheet = nil }
        after {
            environment.router.route = .main
            environment.mainModel.newStation()
        }
        after { window.snapshotSheet(to: directory.appendingPathComponent("04-editor.png")) }
        after { environment.mainModel.editor = nil }
        after { environment.mainModel.setFilter(.favorites) }
        after { window.snapshotPanel(to: directory.appendingPathComponent("05-favorites.png")) }
        after { environment.mainModel.setFilter(.all) }
        after {
            if let station = environment.library.byID("rock-nashe") {
                environment.player.play(station)
            }
        }
        after { }
        after { }
        after { }
        after { window.snapshotPanel(to: directory.appendingPathComponent("08-playing.png")) }
        after { environment.player.stop() }
        after { environment.theme.setPreference(.dark) }
        after { window.snapshotPanel(to: directory.appendingPathComponent("06-dark.png")) }
        after { environment.router.route = .settings }
        after { window.snapshotPanel(to: directory.appendingPathComponent("09-settings-dark.png")) }
        after { environment.router.route = .main }
        after { environment.theme.setPreference(.system) }
        // Hide and immediately re-show: the stale hide animation must not order
        // the panel out after the second show.
        after {
            window.hide()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000)
                window.showMainWindow()
            }
        }
        after {
            DebugLog.write("hide/show race: visible=\(window.isVisible)")
            window.snapshotPanel(to: directory.appendingPathComponent("07-reshown.png"))
        }
        after { NSApp.terminate(nil) }
    }

    // MARK: - Playback smoke test

    private static var playtestCancellables: Set<AnyCancellable> = []

    private static func runPlaytest(output: URL, environment: AppEnvironment) {
        let player = environment.player
        let started = Date()
        var lines: [String] = []
        let ids = ["rock-nashe", "rock-maximum", "soma-groove"]

        func stamp() -> String {
            String(format: "%5.1fs", Date().timeIntervalSince(started))
        }

        player.$status
            .sink { status in
                lines.append("[\(stamp())] state=\(status.rawValue) error=\(player.errorMessage ?? "-")")
            }
            .store(in: &playtestCancellables)

        player.$nowPlaying
            .compactMap { $0 }
            .sink { track in
                lines.append("[\(stamp())] track=\(track.trayLine) artwork=\(track.artworkURL ?? "-")")
            }
            .store(in: &playtestCancellables)

        player.$streamInfo
            .compactMap { $0 }
            .sink { info in
                lines.append(
                    "[\(stamp())] stream codec=\(info.codec) bitrate=\(info.bitrateText) " +
                        "freq=\(info.frequency) channels=\(info.channels) buffer=\(info.bufferMilliseconds)"
                )
            }
            .store(in: &playtestCancellables)

        func step(_ index: Int) {
            guard index < ids.count else {
                lines.append("== done")
                try? lines.joined(separator: "\n").appending("\n")
                    .write(to: output, atomically: true, encoding: .utf8)
                player.stop()
                NSApp.terminate(nil)
                return
            }
            guard let station = environment.library.byID(ids[index])
                ?? environment.library.stations.first
            else {
                lines.append("no station available")
                NSApp.terminate(nil)
                return
            }
            lines.append("== play \(station.name) <\(station.url)>")
            player.play(station)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                step(index + 1)
            }
        }

        step(0)
    }

    // MARK: - Helpers

    /// The app is sandboxed, so artefacts go into the container's temporary folder.
    private static func scratchDirectory(named name: String) -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return name.isEmpty ? base : base.appendingPathComponent(name, isDirectory: true)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}
#endif
