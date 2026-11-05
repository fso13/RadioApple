import Foundation

/// Library helpers for the Finder integration: paths arrive from the Finder
/// instead of the music page, so lookups and mirrored playlists live here.
extension MusicLibrary {
    /// Looks a track up by its absolute path.
    func track(atPath path: String) -> LocalTrack? {
        tracks.first { $0.path == path }
    }

    /// Replaces the content of a playlist that mirrors a folder, keeping its
    /// name and identifier.
    func replaceTracks(_ trackIDs: [String], in playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let valid = trackIDs.filter { id in tracks.contains { $0.id == id } }
        guard playlists[index].trackIDs != valid else { return }
        playlists[index].trackIDs = valid
        playlists[index].updatedAt = Date()
        schedulePersist()
    }
}
