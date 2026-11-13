import SwiftUI

@main
struct RadioiOSApp: App {
    @StateObject private var environment = IOSEnvironment()
    @StateObject private var router = IOSRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(router)
                .environmentObject(environment.settings)
                .environmentObject(environment.theme)
                .environmentObject(environment.library)
                .environmentObject(environment.music)
                .environmentObject(environment.equalizer)
                .environmentObject(environment.player)
                .onOpenURL { url in handle(url) }
        }
    }

    /// `radiomac://play/<station-id>`, `radiomac://pause`, `radiomac://player`,
    /// `radiomac://radio|browser|music|settings`, `radiomac://music/albums`,
    /// `radiomac://music/artists`, `radiomac://music/playlists`,
    /// `radiomac://music/import`.
    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "radiomac" else { return }

        switch url.host?.lowercased() {
        case "play":
            guard let id = url.pathComponents.dropFirst().first,
                  let station = environment.library.byID(id)
            else { return }
            environment.player.play(station)

            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let wantsPlayer = components?.queryItems?.contains {
                $0.name == "player" && $0.value == "1"
            } ?? false
            if wantsPlayer {
                router.showPlayer = true
            }

        case "pause":
            environment.player.pause()

        case "player":
            router.showPlayer = true

        case "radio":
            router.screen = .radio

        case "browser":
            router.screen = .browser

        case "settings":
            router.screen = .settings

        case "music":
            router.screen = .music
            handleMusicPath(url)

        default:
            break
        }
    }

    private func handleMusicPath(_ url: URL) {
        switch url.pathComponents.dropFirst().first?.lowercased() {
        case "albums":
            router.musicPage = .albums
        case "artists":
            router.musicPage = .artists
        case "playlists":
            router.musicPage = .playlists
        case "playlist":
            router.musicPage = .playlists
            router.playlistName = url.pathComponents.dropFirst().dropFirst().first
        case "album":
            router.musicPage = .albums
            router.albumTitle = url.pathComponents.dropFirst().dropFirst().first
        case "artist":
            router.musicPage = .artists
            router.artistName = url.pathComponents.dropFirst().dropFirst().first
        case "import":
            router.musicPage = .allTracks
            router.importSharedMusic = true
        case "media":
            router.musicPage = .allTracks
            router.importMediaLibrary = true
        case "media-all":
            router.musicPage = .allTracks
            router.importAllMediaLibrary = true
        case "media-playlists":
            router.musicPage = .allTracks
            router.importMediaPlaylists = true
        default:
            router.musicPage = .allTracks
        }
    }
}
