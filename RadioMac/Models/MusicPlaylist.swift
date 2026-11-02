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
    case manual
    case added
    case title
    case artist
    case album
    case duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Свой порядок"
        case .added: return "По дате добавления"
        case .title: return "По названию"
        case .artist: return "По исполнителю"
        case .album: return "По альбому"
        case .duration: return "По длительности"
        }
    }
}

/// How the local-music table groups its rows. `none` keeps the flat list.
enum MusicGrouping: String, CaseIterable, Identifiable, Sendable {
    case none
    case artist
    case album
    case genre

    var id: String { rawValue }

    /// Full name shown in the grouping menu.
    var title: String {
        switch self {
        case .none: return "Без группировки"
        case .artist: return "По исполнителю"
        case .album: return "По альбому"
        case .genre: return "По жанру"
        }
    }

    /// Compact name shown in the toolbar control.
    var shortTitle: String {
        switch self {
        case .none: return "Группировка"
        case .artist: return "Исполнитель"
        case .album: return "Альбом"
        case .genre: return "Жанр"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "rectangle.3.group"
        case .artist: return "person"
        case .album: return "square.stack"
        case .genre: return "tag"
        }
    }
}

/// One group of the local-music table: an artist, an album or a genre.
///
/// `id` is built from the grouping and the raw group key, so two artists with
/// an album of the same name produce different sections.
struct MusicTrackSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// Extra context under the title: the artist and year of an album.
    let subtitle: String?
    let tracks: [LocalTrack]
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
