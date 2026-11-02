import Combine
import Foundation

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

/// UI state of the music page: search, picked playlist, sorting and the sheet
/// currently on screen.
@MainActor
final class MusicViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedPlaylistID: String?
    @Published var sort: MusicSortOrder = .added
    @Published var prompt: MusicPlaylistPrompt?
    @Published var editor: LocalTrack?

    /// Incremented to ask the view to focus the search field (⌘F).
    @Published private(set) var focusSearchToken = 0
    /// Incremented to ask the view to give up search focus (Esc).
    @Published private(set) var resignSearchToken = 0

    func focusSearch() {
        focusSearchToken += 1
    }

    func resignSearch() {
        resignSearchToken += 1
    }

    func reset() {
        searchText = ""
        selectedPlaylistID = nil
        prompt = nil
        editor = nil
    }

    func presentCreatePlaylist() {
        prompt = MusicPlaylistPrompt(mode: .create, initialName: "")
    }

    func presentRename(_ playlist: MusicPlaylist) {
        prompt = MusicPlaylistPrompt(mode: .rename(playlist), initialName: playlist.name)
    }
}
