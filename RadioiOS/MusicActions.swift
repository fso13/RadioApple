import Foundation

/// Routes of the local-music navigation stack.
enum MusicRoute: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)
}

/// What the local-music screens can ask the container to do. Keeping the
/// callbacks in one place lets album, artist, playlist and track lists share
/// the same playback, editing and navigation behaviour.
struct MusicActions {
    var play: (LocalTrack, [LocalTrack], String) -> Void
    var playAlbum: (MusicAlbum) -> Void
    var playArtist: (MusicArtist) -> Void
    var playPlaylist: (MusicPlaylist) -> Void

    var openAlbum: (MusicAlbum) -> Void
    var openArtist: (MusicArtist) -> Void
    var openPlaylist: (MusicPlaylist) -> Void

    var editTrack: (LocalTrack) -> Void
    var editAlbumArtwork: (MusicAlbum) -> Void
    var editArtistArtwork: (MusicArtist) -> Void

    var addToNewPlaylist: (LocalTrack) -> Void
    var addTracksToPlaylist: (MusicPlaylist) -> Void
    var removeFromPlaylist: (LocalTrack, MusicPlaylist) -> Void

    var deleteTrack: (LocalTrack) -> Void
    var createPlaylist: () -> Void
    var renamePlaylist: (MusicPlaylist) -> Void
    var deletePlaylist: (MusicPlaylist) -> Void
}

/// A create/rename request for the playlist name sheet.
struct PlaylistPromptRequest: Identifiable {
    enum Mode {
        case create(trackIDs: [String])
        case rename(MusicPlaylist)
    }

    let id = UUID()
    let mode: Mode
    var initialName: String

    var title: String {
        switch mode {
        case .create: return "Новый плейлист"
        case .rename: return "Переименовать плейлист"
        }
    }
}
