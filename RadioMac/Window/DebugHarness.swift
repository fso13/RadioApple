#if DEBUG
@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import SwiftUI

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
        if let name = value(after: "-reconnecttest", in: arguments) {
            runReconnectTest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                environment: environment
            )
            return true
        }
        if let name = value(after: "-eqtest", in: arguments) {
            runEqualizerTest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                environment: environment
            )
            return true
        }
        if let name = value(after: "-nativetest", in: arguments) {
            runNativeTest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                stationID: "rp-soundpark",
                environment: environment
            )
            return true
        }
        if let name = value(after: "-nativeaac", in: arguments) {
            runNativeTest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                stationID: "rock-maximum",
                applyEQ: false,
                environment: environment
            )
            return true
        }
        if let name = value(after: "-nativeeq", in: arguments) {
            runNativeTest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                stationID: "rock-maximum",
                applyEQ: true,
                environment: environment
            )
            return true
        }
        if let name = value(after: "-nativeeqmp3", in: arguments) {
            runNativeTest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                stationID: "rock-nashe",
                applyEQ: true,
                environment: environment
            )
            return true
        }
        if let name = value(after: "-enrichtest", in: arguments) {
            runEnrichmentTest(
                output: scratchDirectory(named: "").appendingPathComponent(name)
            )
            return true
        }
        if let name = value(after: "-musicplaytest", in: arguments) {
            runMusicPlaytest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                environment: environment
            )
            return true
        }
        if let name = value(after: "-hotkeytest", in: arguments) {
            let output = scratchDirectory(named: "").appendingPathComponent(name)
            let lines = [
                "playPause=\(environment.hotKeys.playPause.display)",
                "next=\(environment.hotKeys.nextStation.display)",
                "error=\(environment.hotKeys.errorText)",
            ]
            try? lines.joined(separator: "\n").appending("\n").write(
                to: output, atomically: true, encoding: .utf8
            )
            NSApp.terminate(nil)
            return true
        }
        if let name = value(after: "-rbtest", in: arguments) {
            runRadioBrowserTest(
                output: scratchDirectory(named: "").appendingPathComponent(name)
            )
            return true
        }
        if let name = value(after: "-nativeeqhls", in: arguments) {
            runNativeTest(
                output: scratchDirectory(named: "").appendingPathComponent(name),
                stationID: "rp-soundpark",
                applyEQ: true,
                environment: environment
            )
            return true
        }
        return false
    }

    // MARK: - Local music

    /// Checks the online catalogues and the match scoring against live APIs.
    private static func runEnrichmentTest(output: URL) {
        Task { @MainActor in
            let queries = [
                ("Gymnopedie No. 1", "Erik Satie"),
                ("Clair de Lune", "Claude Debussy"),
                ("Peace Piece", "Bill Evans"),
                ("Some Song That Cannot Exist 9x8y7z", "Nobody"),
            ]
            var lines: [String] = []
            for (title, artist) in queries {
                let found = await MetadataEnrichmentService.shared.candidates(
                    title: title,
                    artist: artist,
                    album: nil
                )
                lines.append("query=\(title) count=\(found.count)")
                for candidate in found.prefix(3) {
                    lines.append(
                        "  score=\(String(format: "%.2f", candidate.matchScore)) "
                            + "title=\(candidate.title ?? "-") "
                            + "artist=\(candidate.artist ?? "-") "
                            + "album=\(candidate.album ?? "-") "
                            + "year=\(candidate.year.map(String.init) ?? "-") "
                            + "genre=\(candidate.genre ?? "-") "
                            + "art=\(candidate.artworkURL != nil) "
                            + "source=\(candidate.source)"
                    )
                }
            }
            try? lines.joined(separator: "\n").appending("\n").write(
                to: output,
                atomically: true,
                encoding: .utf8
            )
            NSApp.terminate(nil)
        }
    }

    /// Plays the sample WAVs and records the player state, so the local queue
    /// and auto-advance can be checked without clicking through the UI.
    private static func runMusicPlaytest(output: URL, environment: AppEnvironment) {
        seedMusicSnapshot(environment: environment)
        let tracks = environment.music.sorted(environment.music.tracks, by: .title)
        environment.player.playLocalTracks(tracks, startingAt: 0, title: "test")
        let player = environment.player

        var lines: [String] = []
        Task { @MainActor in
            for step in 0..<12 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                lines.append(
                    "t=\(Double(step) * 0.5) status=\(player.status.rawValue) "
                        + "track=\(player.localTrack?.displayTitle ?? "-") "
                        + "playing=\(player.isPlaying) "
                        + "elapsed=\(String(format: "%.2f", player.playbackElapsed)) "
                        + "duration=\(player.playbackDuration ?? -1) "
                        + "queue=\(player.localQueue.count) "
                        + "now=\(player.nowPlaying?.trayLine ?? "-")"
                )
            }
            lines.append("error=\(player.consumeError() ?? "none")")
            try? lines.joined(separator: "\n").appending("\n").write(
                to: output,
                atomically: true,
                encoding: .utf8
            )
            NSApp.terminate(nil)
        }
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
        after {
            snapshotHosting(
                MiniPlayerView(
                    player: environment.player,
                    library: environment.library,
                    music: environment.music,
                    theme: environment.theme,
                    onOpenWindow: {}
                ),
                size: NSSize(width: 320, height: 430),
                to: directory.appendingPathComponent("12-mini-player.png")
            )
        }
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
        after {
            snapshotHosting(
                ThemedRoot {
                    RadioBrowserView(
                        library: environment.library,
                        player: environment.player,
                        toasts: environment.toasts
                    )
                },
                size: NSSize(width: 760, height: 610),
                to: directory.appendingPathComponent("10-radio-browser.png")
            )
        }
        after {
            snapshotHosting(
                ThemedRoot {
                    StationTransferView(
                        library: environment.library,
                        toasts: environment.toasts
                    )
                },
                size: NSSize(width: 660, height: 470),
                to: directory.appendingPathComponent("11-transfer.png")
            )
        }
        seedMusicSnapshot(environment: environment)
        after { environment.router.route = .music }
        after { }
        after { window.snapshotPanel(to: directory.appendingPathComponent("13-music.png")) }
        after {
            let items = environment.music.sorted(environment.music.tracks, by: .title)
            guard !items.isEmpty else { return }
            environment.player.playLocalTracks(items, startingAt: 0, title: "Все треки")
        }
        after { }
        after { window.snapshotPanel(to: directory.appendingPathComponent("14-music-playing.png")) }
        after {
            snapshotHosting(
                MiniPlayerView(
                    player: environment.player,
                    library: environment.library,
                    music: environment.music,
                    theme: environment.theme,
                    onOpenWindow: {}
                ),
                size: NSSize(width: 320, height: 430),
                to: directory.appendingPathComponent("18-mini-player-music.png")
            )
        }
        after {
            environment.player.stop()
            environment.theme.setPreference(.dark)
        }
        after { window.snapshotPanel(to: directory.appendingPathComponent("15-music-dark.png")) }
        after {
            environment.theme.setPreference(.system)
            environment.router.route = .settings
        }
        after {
            if let track = environment.music.tracks.first {
                snapshotHosting(
                    ThemedRoot {
                        MusicTrackEditorView(track: track, library: environment.music)
                    },
                    size: NSSize(width: 560, height: 720),
                    to: directory.appendingPathComponent("16-music-editor.png")
                )
            }
        }
        after {
            snapshotHosting(
                ThemedRoot {
                    MusicSourcesView(
                        library: environment.music,
                        toasts: environment.toasts,
                        onClose: {}
                    )
                },
                size: NSSize(width: 620, height: 560),
                to: directory.appendingPathComponent("17-music-sources.png")
            )
        }
        after { NSApp.terminate(nil) }
    }

    /// Snapshot helper: a few silent WAVs with tag-like file names, installed
    /// in memory so the developer's own library is untouched.
    private static func seedMusicSnapshot(environment: AppEnvironment) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RadioMacSnapshotMusic", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let names = [
            "01 - Erik Satie - Gymnopedie No. 1.wav",
            "02 - Claude Debussy - Clair de Lune.wav",
            "03 - Bill Evans - Peace Piece.wav",
            "04 - Nils Frahm - Says.wav",
            "05 - Philip Glass - Opening.wav",
        ]
        let albums = ["Quiet Piano", "Quiet Piano", "Kind of Blue", "Spaces", "Glassworks"]

        var tracks: [LocalTrack] = []
        for (index, name) in names.enumerated() {
            let url = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                writeSilentWav(to: url, seconds: 3)
            }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let fallback = LocalAudioMetadata.fallback(from: url)
            tracks.append(
                LocalTrack(
                    path: url.path,
                    title: fallback.title,
                    artist: fallback.artist,
                    album: albums[index],
                    genre: index == 2 ? "Jazz" : "Ambient",
                    year: 2016,
                    trackNumber: index + 1,
                    duration: 3,
                    addedAt: Date(timeIntervalSinceNow: TimeInterval(-index * 3600))
                )
            )
        }
        let playlist = MusicPlaylist(
            name: "Для работы",
            trackIDs: tracks.prefix(3).map(\.id),
            sourceName: "work.m3u"
        )
        environment.music.debugInstall(tracks: tracks, playlists: [playlist])
    }

    private static func writeSilentWav(to url: URL, seconds: Int) {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 1
        ) else { return }
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else {
            return
        }
        let frames = AVAudioFrameCount(44_100 * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return
        }
        buffer.frameLength = frames
        try? file.write(from: buffer)
    }

    private static func snapshotHosting<Content: View>(
        _ content: Content,
        size: NSSize,
        to url: URL
    ) {
        let hosting = NSHostingView(
            rootView: content.environment(\.colorScheme, .light)
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    // MARK: - Playback smoke test

    private static var playtestCancellables: Set<AnyCancellable> = []

    private static func runReconnectTest(output: URL, environment: AppEnvironment) {
        let player = environment.player
        player.stop()
        playtestCancellables.removeAll()

        var lines: [String] = []
        let started = Date()
        func stamp() -> String {
            String(format: "%5.1fs", Date().timeIntervalSince(started))
        }

        player.$status
            .sink { status in
                let attempts = player.reconnectAttempts
                let error = player.errorMessage ?? "-"
                lines.append("[\(stamp())] state=\(status.rawValue) attempts=\(attempts) error=\(error)")
            }
            .store(in: &playtestCancellables)

        let station = RadioStation(
            id: "reconnect-test",
            name: "Reconnect Test",
            url: "https://127.0.0.1:1/nope",
            genre: "Test"
        )
        lines.append("== reconnect \(station.url)")
        player.play(station)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 22_000_000_000)
            lines.append("[22.0s] before manual retry state=\(player.status.rawValue) attempts=\(player.reconnectAttempts)")
            player.retryNow()

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            lines.append("[25.0s] after manual retry state=\(player.status.rawValue) attempts=\(player.reconnectAttempts)")
            player.stop()
            try? lines.joined(separator: "\n").appending("\n").write(
                to: output,
                atomically: true,
                encoding: .utf8
            )
            NSApp.terminate(nil)
        }
    }

    private static func runEqualizerTest(output: URL, environment: AppEnvironment) {
        let player = environment.player
        let equalizer = environment.equalizer
        let previousEnabled = equalizer.enabled
        let previousPreset = equalizer.presetID
        let previousGains = equalizer.gains

        player.stop()
        playtestCancellables.removeAll()

        var lines: [String] = []
        let started = Date()
        func stamp() -> String {
            String(format: "%5.1fs", Date().timeIntervalSince(started))
        }

        player.$status
            .sink { status in
                let engine = player.activeEngineName
                let eq = equalizer.enabled
                let supported = equalizer.isSupported
                lines.append("[\(stamp())] state=\(status.rawValue) engine=\(engine) eq=\(eq) supported=\(supported)")
            }
            .store(in: &playtestCancellables)

        guard let station = environment.library.byID("rock-nashe")
            ?? environment.library.stations.first
        else {
            try? "no station\n".write(to: output, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }

        lines.append("== eq \(station.name) <\(station.url)>")
        player.play(station)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            equalizer.setEnabled(true)
            equalizer.setBand(5, value: 8)
            equalizer.setBand(0, value: 4)
            lines.append("[ 2.0s] eq enabled on native DSP")

            try? await Task.sleep(nanoseconds: 8_000_000_000)
            lines.append("[10.0s] final state=\(player.status.rawValue) eq=\(equalizer.enabled) supported=\(equalizer.isSupported)")
            player.stop()
            equalizer.applyPreset(previousPreset)
            for (index, gain) in previousGains.enumerated() {
                equalizer.setBand(index, value: gain)
            }
            if previousEnabled {
                equalizer.setEnabled(true)
            } else {
                equalizer.setEnabled(false)
            }
            try? lines.joined(separator: "\n").appending("\n").write(
                to: output,
                atomically: true,
                encoding: .utf8
            )
            NSApp.terminate(nil)
        }
    }

    private static func runRadioBrowserTest(output: URL) {
        let service = RadioBrowserService()
        service.search(name: "jazz", genre: "", country: "")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            var lines = [
                "error=\(service.errorText)",
                "loading=\(service.isLoading)",
                "count=\(service.results.count)",
            ]
            for item in service.results.prefix(5) {
                lines.append("\(item.name) | \(item.country ?? "-") | \(item.streamURL ?? "-")")
            }
            try? lines.joined(separator: "\n").appending("\n").write(
                to: output, atomically: true, encoding: .utf8
            )
            NSApp.terminate(nil)
        }
    }

    private static func runNativeTest(output: URL, stationID: String, applyEQ: Bool = false, environment: AppEnvironment) {
        let player = environment.player
        let equalizer = environment.equalizer
        player.stop()
        playtestCancellables.removeAll()

        var lines: [String] = []
        let started = Date()
        func stamp() -> String {
            String(format: "%5.1fs", Date().timeIntervalSince(started))
        }

        player.$status
            .sink { status in
                lines.append("[\(stamp())] state=\(status.rawValue) engine=\(player.activeEngineName) error=\(player.errorMessage ?? "-")")
            }
            .store(in: &playtestCancellables)

        player.$nowPlaying
            .compactMap { $0 }
            .sink { track in
                lines.append("[\(stamp())] track=\(track.trayLine)")
            }
            .store(in: &playtestCancellables)

        guard let station = environment.library.byID(stationID)
            ?? environment.library.stations.first(where: { $0.url.contains(".m3u8") })
        else {
            try? "no HLS station\n".write(to: output, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }

        lines.append("== native \(station.name) <\(station.url)> applyEQ=\(applyEQ)")
        player.play(station)

        Task { @MainActor in
            if applyEQ {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                equalizer.setEnabled(true)
                equalizer.setBand(5, value: 8)
                lines.append("[ 2.0s] native EQ enabled")
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            } else {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
            let info = player.streamInfo
            lines.append(
                "[10.0s] final state=\(player.status.rawValue) engine=\(player.activeEngineName) "
                    + "codec=\(info?.codec ?? "-") rate=\(info?.sampleRateText ?? "-") "
                    + "channels=\(info?.channelsText ?? "-") bitrate=\(info?.bitrateText ?? "-") "
                    + "buffer=\(info?.bufferText ?? "-") server=\(info?.serverText ?? "-")"
            )
            player.stop()
            try? lines.joined(separator: "\n").appending("\n").write(
                to: output,
                atomically: true,
                encoding: .utf8
            )
            NSApp.terminate(nil)
        }
    }

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
