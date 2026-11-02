import Foundation

/// One audio file from the user's own music folders.
///
/// The track keeps both what the file's tags say and what the online enrichment
/// found: tags are never rewritten on disk, everything lives in the library.
struct LocalTrack: Identifiable, Hashable, Codable, Sendable {
    var id: String
    /// Absolute path of the audio file.
    var path: String
    /// Tag title. Empty when the file has no title tag — `displayTitle` then
    /// falls back to the file name, so the table never shows a blank row.
    var title: String
    var artist: String?
    var album: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var duration: TimeInterval?
    /// Cover: either a cached `file://` image or a remote URL from enrichment.
    var artworkURL: String?
    var addedAt: Date
    var enrichedAt: Date?
    var enrichmentSource: String?
    /// The file is gone (folder moved, drive unplugged) but the row is kept.
    var isMissing: Bool

    init(
        id: String = UUID().uuidString,
        path: String,
        title: String = "",
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        duration: TimeInterval? = nil,
        artworkURL: String? = nil,
        addedAt: Date = Date(),
        enrichedAt: Date? = nil,
        enrichmentSource: String? = nil,
        isMissing: Bool = false
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.duration = duration
        self.artworkURL = artworkURL
        self.addedAt = addedAt
        self.enrichedAt = enrichedAt
        self.enrichmentSource = enrichmentSource
        self.isMissing = isMissing
    }

    // MARK: - Derived

    var url: URL { URL(fileURLWithPath: path) }

    var fileName: String { url.lastPathComponent }

    var displayTitle: String {
        if let value = Self.trimmed(title) { return value }
        return url.deletingPathExtension().lastPathComponent
    }

    var displayArtist: String? { Self.trimmed(artist) }

    var displayAlbum: String? { Self.trimmed(album) }

    var displayGenre: String? { Self.trimmed(genre) }

    /// `Artist — Album`, with the missing half dropped.
    var subtitle: String {
        [displayArtist, displayAlbum]
            .compactMap { $0 }
            .joined(separator: " — ")
    }

    /// `Artist — Title` for the menu bar and the now-playing line.
    var trayLine: String {
        if let artist = displayArtist { return "\(artist) — \(displayTitle)" }
        return displayTitle
    }

    var hasArtwork: Bool {
        guard let artworkURL = Self.trimmed(artworkURL) else { return false }
        return !artworkURL.isEmpty
    }

    var durationText: String? { Self.format(duration) }

    /// Rows worth asking the online service about.
    var needsEnrichment: Bool {
        guard !isMissing else { return false }
        return displayAlbum == nil || !hasArtwork
    }

    var searchText: String {
        [displayTitle, displayArtist ?? "", displayAlbum ?? "", displayGenre ?? "", fileName]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
    }

    // MARK: - Formatting

    static func format(_ duration: TimeInterval?) -> String? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func totalDurationText(_ tracks: [LocalTrack]) -> String {
        let total = tracks.compactMap(\.duration).reduce(0, +)
        guard total > 0 else { return "—" }
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 { return "\(hours) ч \(minutes) мин" }
        return "\(max(1, minutes)) мин"
    }

    // MARK: - JSON

    private enum CodingKeys: String, CodingKey {
        case id, path, title, artist, album, genre, year, trackNumber, duration
        case artworkUrl, addedAt, enrichedAt, enrichmentSource, isMissing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .artist))
        album = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .album))
        genre = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .genre))
        year = Self.validYear(try container.decodeIfPresent(Int.self, forKey: .year))
        trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        artworkURL = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .artworkUrl))
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        enrichedAt = try container.decodeIfPresent(Date.self, forKey: .enrichedAt)
        enrichmentSource = Self.trimmed(
            try container.decodeIfPresent(String.self, forKey: .enrichmentSource)
        )
        isMissing = try container.decodeIfPresent(Bool.self, forKey: .isMissing) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(trackNumber, forKey: .trackNumber)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(artworkURL, forKey: .artworkUrl)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(enrichedAt, forKey: .enrichedAt)
        try container.encodeIfPresent(enrichmentSource, forKey: .enrichmentSource)
        try container.encode(isMissing, forKey: .isMissing)
    }

    // MARK: - Helpers

    static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    static func validYear(_ value: Int?) -> Int? {
        guard let value, (1500...2999).contains(value) else { return nil }
        return value
    }
}
