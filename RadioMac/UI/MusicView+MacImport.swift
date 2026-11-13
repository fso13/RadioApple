import SwiftUI

extension MusicView {
    /// Applies Music.app tags and maps persistent IDs to local track IDs.
    func applyMacMusicMetadata(_ items: [MacMusicTrack]) -> [String: String] {
        var byPath: [String: LocalTrack] = [:]
        for track in library.tracks {
            byPath[track.path] = track
        }

        var mapping: [String: String] = [:]
        for item in items {
            guard let url = item.location else { continue }
            let path = url.standardizedFileURL.path
            guard var track = byPath[path] else { continue }

            track.mediaLibraryID = item.id
            if !item.title.isEmpty { track.title = item.title }
            if let artist = item.artist { track.artist = artist }
            if let album = item.album { track.album = album }
            if let genre = item.genre { track.genre = genre }
            if let duration = item.duration, duration > 0 {
                track.duration = duration
            }

            library.update(track)
            byPath[path] = track
            mapping[item.id] = track.id
        }
        return mapping
    }

    /// Merges Music.app user playlists into the library without duplicating
    /// playlists or tracks.
    func importMacMusicPlaylists(
        _ playlists: [MacMusicPlaylist],
        mapping: [String: String]
    ) -> Int {
        var imported = 0

        for playlist in playlists {
            var seen: Set<String> = []
            let trackIDs: [String] = playlist.trackIDs.compactMap { mediaID -> String? in
                guard let trackID = mapping[mediaID],
                      seen.insert(trackID).inserted
                else { return nil }
                return trackID
            }
            guard !trackIDs.isEmpty else { continue }

            if let existing = library.playlists.first(where: {
                $0.name.localizedCaseInsensitiveCompare(playlist.name) == .orderedSame
            }) {
                library.addTracks(trackIDs, to: existing.id)
            } else {
                library.createPlaylist(name: playlist.name, trackIDs: trackIDs)
            }
            imported += 1
        }

        return imported
    }
}
