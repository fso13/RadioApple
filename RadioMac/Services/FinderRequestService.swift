import AppKit
import Combine
import Foundation

/// Handles the items a Finder context-menu action hands to RadioMac: audio
/// files start playing, a folder becomes a playlist of its audio files.
///
/// Items normally arrive through Launch Services (`application(_:open:)`),
/// which also grants the sandboxed app read access to them. The Finder Sync
/// extension additionally posts a distributed notification, used when Launch
/// Services refused to open the items with the app.
@MainActor
final class FinderRequestService {
    private let environment: AppEnvironment
    private let showMusicWindow: () -> Void
    private var cancellable: AnyCancellable?

    init(environment: AppEnvironment, showMusic: @escaping () -> Void) {
        self.environment = environment
        self.showMusicWindow = showMusic
    }

    /// Subscribes to the extension's fallback channel.
    func start() {
        cancellable = DistributedNotificationCenter.default()
            .publisher(for: FinderBridge.notificationName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let request = FinderBridge.request(from: notification.userInfo) else { return }
                MainActor.assumeIsolated {
                    self?.handle(request)
                }
            }
    }

    /// Entry point for `NSApplicationDelegate.application(_:open:)`.
    func handleOpenDocuments(_ urls: [URL]) {
        var folders: [URL] = []
        var audio: [URL] = []
        for url in urls where url.isFileURL {
            if FinderMenuPlanner.isFolder(url) {
                folders.append(url)
            } else {
                audio.append(url)
            }
        }

        folders.forEach(createPlaylist)
        if !audio.isEmpty { play(audio) }
    }

    private func handle(_ request: FinderRequest) {
        let urls = request.paths.map { URL(fileURLWithPath: $0) }
        switch request.action {
        case .playAudio:
            play(urls)
        case .createPlaylist:
            urls.forEach(createPlaylist)
        }
    }

    // MARK: - Audio files

    private func play(_ urls: [URL]) {
        let paths = uniquePaths(of: urls)
        guard !paths.isEmpty else { return }
        showMusicWindow()

        Task { @MainActor [environment] in
            let music = environment.music
            let unknown = paths.filter { music.track(atPath: $0) == nil }
            if !unknown.isEmpty {
                await music.addFiles(unknown.map { URL(fileURLWithPath: $0) })
            }

            let tracks = paths.compactMap { music.track(atPath: $0) }.filter { !$0.isMissing }
            guard !tracks.isEmpty else {
                let name = URL(fileURLWithPath: paths[0]).lastPathComponent
                environment.toasts.show(
                    "Не удалось открыть «\(name)». Добавьте папку в источниках музыки",
                    kind: .error
                )
                return
            }
            music.flush()
            environment.player.playLocalTracks(
                tracks,
                startingAt: 0,
                title: tracks.count > 1 ? "Выбранное в Finder" : nil
            )
        }
    }

    private func uniquePaths(of urls: [URL]) -> [String] {
        var seen: Set<String> = []
        return urls
            .map(\.standardizedFileURL.path)
            .filter { seen.insert($0).inserted }
    }

    // MARK: - Folders

    private func createPlaylist(for folder: URL) {
        let standardized = folder.standardizedFileURL
        let name = standardized.lastPathComponent
        guard !name.isEmpty else { return }
        showMusicWindow()

        Task { @MainActor [environment] in
            let music = environment.music
            guard Self.isReadableDirectory(standardized) else {
                environment.toasts.show(
                    "Нет доступа к папке «\(name)». Добавьте её в источниках музыки",
                    kind: .error
                )
                return
            }

            await music.addFolder(standardized)
            let prefix = standardized.path + "/"
            let trackIDs = music.tracks
                .filter { $0.path == standardized.path || $0.path.hasPrefix(prefix) }
                .map(\.id)
            guard !trackIDs.isEmpty else {
                environment.toasts.show("В папке «\(name)» нет аудиофайлов", kind: .info)
                return
            }
            music.flush()

            // The same folder keeps one playlist: a second run refreshes its
            // tracks instead of piling up «Джаз 2», «Джаз 3»…
            if let existing = music.playlists.first(where: { $0.folderPath == standardized.path }) {
                music.replaceTracks(trackIDs, in: existing.id)
                environment.musicModel.openPlaylist(existing.id)
                environment.toasts.show(
                    "Плейлист «\(existing.name)» обновлён: \(MusicCount.tracks(trackIDs.count))",
                    kind: .success
                )
                return
            }

            guard let playlist = music.createPlaylist(
                name: name,
                trackIDs: trackIDs,
                folderPath: standardized.path
            ) else { return }
            environment.musicModel.openPlaylist(playlist.id)
            environment.toasts.show(
                "Плейлист «\(playlist.name)»: \(MusicCount.tracks(trackIDs.count))",
                kind: .success
            )
        }
    }

    private static func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }
}
