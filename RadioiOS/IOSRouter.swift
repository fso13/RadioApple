import Combine
import Foundation

/// Navigation state that URL schemes and the UI share: which tab is visible,
/// whether the full player is open, and one-shot music requests.
@MainActor
final class IOSRouter: ObservableObject {
    enum Screen: Hashable {
        case radio
        case browser
        case music
        case settings
    }

    @Published var screen: Screen = .radio
    @Published var showPlayer = false
    /// One-shot request to open a music page (`radiomac://music/albums`).
    @Published var musicPage: MusicPage?
    /// One-shot request to import audio dropped into `Documents/Music`.
    @Published var importSharedMusic = false
    /// One-shot request to open a playlist, album or artist by name.
    @Published var playlistName: String?
    @Published var albumTitle: String?
    @Published var artistName: String?
}
