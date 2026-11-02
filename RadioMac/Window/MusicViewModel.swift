import Combine
import Foundation

/// Top-level pages of the local-music window.
enum MusicPage: String, CaseIterable, Identifiable, Sendable {
    case allTracks
    case albums
    case artists
    case playlists

    var id: String { rawValue }
}

/// Sheet asking for a playlist name.
struct MusicPlaylistPrompt: Identifiable {
    enum Mode: Equatable {
        case create
        case rename(MusicPlaylist)
    }

    let id = UUID()
    var mode: Mode
    var initialName: String

}

/// UI state of the music page: search, picked page, playlist, albums, artists,
/// sorting and the sheet currently on screen.
@MainActor
final class MusicViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var page: MusicPage = .allTracks
    /// Non-nil when the playlist page shows the tracks of one playlist.
    @Published var selectedPlaylistID: String?
    /// Non-nil when the albums page shows one album.
    @Published var selectedAlbumID: String?
    /// Artist the album was opened from, so "back" returns to the artist page.
    @Published var albumParentArtistID: String?
    /// Non-nil when the artists page shows one artist.
    @Published var selectedArtistID: String?
    /// Sidebar disclosure state; only one collection list stays open.
    @Published var albumsExpanded = false
    @Published var artistsExpanded = false
    @Published var sort: MusicSortOrder {
        didSet {
            guard sort != oldValue else { return }
            defaults.set(sort.rawValue, forKey: DefaultsKey.musicSortOrder)
        }
    }
    @Published var grouping: MusicGrouping = .none
    @Published var prompt: MusicPlaylistPrompt?
    @Published var editor: LocalTrack?

    private let defaults: UserDefaults

    /// Incremented to ask the view to focus the search field (⌘F).
    @Published private(set) var focusSearchToken = 0
    /// Incremented to ask the view to give up search focus (Esc).
    @Published private(set) var resignSearchToken = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: DefaultsKey.musicSortOrder)
        sort = stored.flatMap(MusicSortOrder.init(rawValue:)) ?? .added
    }

    func focusSearch() {
        focusSearchToken += 1
    }

    func resignSearch() {
        resignSearchToken += 1
    }

    /// Opens a top-level page and drops any detail selection.
    func show(_ page: MusicPage) {
        self.page = page
        selectedPlaylistID = nil
        selectedAlbumID = nil
        albumParentArtistID = nil
        selectedArtistID = nil
        searchText = ""
    }

    func openAlbum(_ id: String, from artistID: String? = nil) {
        page = .albums
        selectedAlbumID = id
        albumParentArtistID = artistID
        selectedArtistID = nil
        selectedPlaylistID = nil
        searchText = ""
    }

    func openArtist(_ id: String) {
        page = .artists
        selectedArtistID = id
        selectedAlbumID = nil
        albumParentArtistID = nil
        selectedPlaylistID = nil
        searchText = ""
    }

    func openPlaylist(_ id: String) {
        page = .playlists
        selectedPlaylistID = id
        selectedAlbumID = nil
        albumParentArtistID = nil
        selectedArtistID = nil
        searchText = ""
    }

    func reset() {
        searchText = ""
        page = .allTracks
        selectedPlaylistID = nil
        selectedAlbumID = nil
        albumParentArtistID = nil
        selectedArtistID = nil
        albumsExpanded = false
        artistsExpanded = false
        prompt = nil
        editor = nil
    }

    func presentCreatePlaylist() {
        prompt = MusicPlaylistPrompt(mode: .create, initialName: "")
    }

    func presentRename(_ playlist: MusicPlaylist) {
        prompt = MusicPlaylistPrompt(mode: .rename(playlist), initialName: playlist.name)
    }

    func toggleAlbums() {
        albumsExpanded.toggle()
        if albumsExpanded { artistsExpanded = false }
    }

    func toggleArtists() {
        artistsExpanded.toggle()
        if artistsExpanded { albumsExpanded = false }
    }
}
