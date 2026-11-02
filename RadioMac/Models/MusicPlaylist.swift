import Foundation

/// A user-created or M3U-imported playlist. It stores track identifiers, so a
/// track can live in several playlists without being copied.
struct MusicPlaylist: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var trackIDs: [String]
    var createdAt: Date
    var updatedAt: Date
    /// Name of the `.m3u` file the playlist came from, when it did.
    var sourceName: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        trackIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceName = sourceName
    }

    var trackCount: Int { trackIDs.count }
}

/// A folder or a single file the user granted access to. `bookmark` is a
/// security-scoped bookmark, so the grant survives app relaunches.
struct MusicSource: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var path: String
    var isFolder: Bool
    var bookmark: Data?
    var addedAt: Date

    init(
        id: String = UUID().uuidString,
        path: String,
        isFolder: Bool,
        bookmark: Data? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.isFolder = isFolder
        self.bookmark = bookmark
        self.addedAt = addedAt
    }

    var url: URL { URL(fileURLWithPath: path) }

    var displayName: String { url.lastPathComponent }
}

enum MusicSortOrder: String, CaseIterable, Identifiable, Sendable {
    case added
    case title
    case artist
    case album
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .added: return "По дате добавления"
        case .title: return "По названию"
        case .artist: return "По исполнителю"
        case .album: return "По альбому"
        case .duration: return "По длительности"
        }
    }
}

/// Result of importing files, folders or an M3U playlist.
struct MusicImportSummary: Equatable, Sendable {
    var added = 0
    var skipped = 0
    var missing = 0
    var errors: [String] = []

}

struct MusicPlaylistImportResult: Equatable, Sendable {
    var playlistID: String
    var name: String
    var addedTracks: Int
    var skippedEntries: Int
}
