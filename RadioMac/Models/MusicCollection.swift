import Foundation

/// Russian counters for the local-music views: `5 треков`, `2 альбома`.
enum MusicCount {
    static func tracks(_ count: Int) -> String {
        "\(count) \(plural(count, "трек", "трека", "треков"))"
    }

    static func albums(_ count: Int) -> String {
        "\(count) \(plural(count, "альбом", "альбома", "альбомов"))"
    }

    static func artists(_ count: Int) -> String {
        "\(count) \(plural(count, "исполнитель", "исполнителя", "исполнителей"))"
    }

    static func playlists(_ count: Int) -> String {
        "\(count) \(plural(count, "плейлист", "плейлиста", "плейлистов"))"
    }

    private static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if (11...14).contains(mod100) { return many }
        switch mod10 {
        case 1: return one
        case 2, 3, 4: return few
        default: return many
        }
    }
}

/// An album derived from the tracks in the local library.
struct MusicAlbum: Identifiable, Hashable, Sendable {
    /// Stable grouping key, shared with `MusicLibrary.sections`.
    let id: String
    let title: String
    let artist: String?
    let year: Int?
    /// Tracks in album order: track number, then title.
    let tracks: [LocalTrack]
    /// The "no album tag" bucket is not a real album and has no cover editing.
    let isUnnamed: Bool

    var trackCount: Int { tracks.count }

    var durationText: String { LocalTrack.totalDurationText(tracks) }

    /// A cover shared by the album: the first track that has artwork.
    var artworkURL: String? {
        tracks.first { $0.hasArtwork }?.artworkURL
    }

    /// `2019 · 12 треков`; the artist is shown separately.
    var details: String {
        [year.map(String.init), MusicCount.tracks(trackCount)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var searchText: String {
        ([title, artist ?? ""] + tracks.map(\.displayTitle))
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
    }
}

/// An artist derived from the tracks in the local library.
struct MusicArtist: Identifiable, Hashable, Sendable {
    /// Stable grouping key, shared with `MusicLibrary.sections`.
    let id: String
    let name: String
    let albums: [MusicAlbum]
    let tracks: [LocalTrack]
    /// A manually picked cover or a cover of one of the artist's albums.
    let artworkURL: String?
    let isUnnamed: Bool

    var trackCount: Int { tracks.count }

    var albumCount: Int { albums.count }

    var durationText: String { LocalTrack.totalDurationText(tracks) }

    /// `3 альбома · 28 треков`.
    var details: String {
        "\(MusicCount.albums(albumCount)) · \(MusicCount.tracks(trackCount))"
    }

    var searchText: String {
        ([name] + albums.map(\.title))
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
    }
}
