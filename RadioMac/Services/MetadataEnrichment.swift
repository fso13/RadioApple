import Foundation

/// A candidate match returned by an online catalogue.
struct TrackEnrichment: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var year: Int?
    var genre: String?
    var artworkURL: String?
    /// Human-readable provider name, e.g. "Apple Music".
    var source: String
    /// Filled by `TrackMatch`; 0…1.
    var matchScore: Double = 0

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && year == nil
            && genre == nil && artworkURL == nil
    }

    /// How many useful fields the candidate brings. Used to break score ties
    /// in favour of the richer catalogue entry.
    var completeness: Int {
        [album != nil, year != nil, genre != nil, artworkURL != nil]
            .filter { $0 }
            .count
    }

    /// What applying this match would actually change on a track.
    func changes(for track: LocalTrack) -> EnrichmentChanges {
        var changes = EnrichmentChanges()
        if let album, track.displayAlbum == nil { changes.album = album }
        if let artist, track.displayArtist == nil { changes.artist = artist }
        if let genre, track.displayGenre == nil { changes.genre = genre }
        if let year, track.year == nil { changes.year = year }
        if let artworkURL, !track.hasArtwork { changes.artworkURL = artworkURL }
        if let title, track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !title.isEmpty {
            changes.title = title
        }
        return changes
    }

    /// A one-line summary for the UI, e.g. `Album · 2019 · Apple Music`.
    var summary: String {
        [
            album,
            year.map(String.init),
            genre,
            source,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct EnrichmentChanges: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var year: Int?
    var genre: String?
    var artworkURL: String?

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && year == nil
            && genre == nil && artworkURL == nil
    }

    /// How many useful fields the candidate brings. Used to break score ties
    /// in favour of the richer catalogue entry.
    var completeness: Int {
        [album != nil, year != nil, genre != nil, artworkURL != nil]
            .filter { $0 }
            .count
    }
}

struct TrackQuery: Sendable, Hashable {
    var title: String
    var artist: String?
    var album: String?

    var key: String {
        [
            TrackMatch.normalised(title),
            TrackMatch.normalised(artist ?? ""),
            TrackMatch.normalised(album ?? ""),
        ].joined(separator: "|")
    }
}

/// String normalisation and matching shared by every provider.
enum TrackMatch {
    static let acceptThreshold = 0.62

    static func normalised(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        // "(Remastered 2011)", "[Live]", "{Deluxe}" rarely help matching.
        let stripped = folded.replacingOccurrences(
            of: #"[\(\[\{][^\)\]\}]*[\)\]\}]"#,
            with: " ",
            options: .regularExpression
        )
        let cleaned = stripped.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return String(scalar)
            }
            return " "
        }
        .joined()
        return cleaned
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs.contains(rhs) || rhs.contains(lhs) { return 0.85 }
        let left = Set(lhs.split(separator: " "))
        let right = Set(rhs.split(separator: " "))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let overlap = Double(left.intersection(right).count)
        let union = Double(left.union(right).count)
        guard union > 0 else { return 0 }
        return overlap / union * 0.9
    }

    static func score(query: TrackQuery, candidate: TrackEnrichment) -> Double {
        let title = similarity(
            normalised(query.title),
            normalised(candidate.title ?? "")
        )
        guard title > 0 else { return 0 }

        var score = title
        if let artist = query.artist, !normalised(artist).isEmpty {
            if let candidateArtist = candidate.artist, !normalised(candidateArtist).isEmpty {
                let artistScore = similarity(normalised(artist), normalised(candidateArtist))
                score = title * 0.65 + artistScore * 0.35
                if artistScore < 0.2 { score *= 0.75 }
            } else {
                score *= 0.9
            }
        }
        if let album = query.album, !normalised(album).isEmpty,
           let candidateAlbum = candidate.album {
            let albumScore = similarity(normalised(album), normalised(candidateAlbum))
            score += min(0.1, albumScore * 0.1)
        }
        if candidate.artworkURL != nil { score += 0.03 }
        return min(1, score)
    }
}

protocol TrackMetadataProvider: Sendable {
    var name: String { get }
    func search(_ query: TrackQuery) async -> [TrackEnrichment]
}

/// Looks up covers, albums and years of local files in online catalogues.
///
/// The service is provider-agnostic: Apple Music's iTunes Search API answers
/// first, Deezer fills the gaps for releases iTunes does not index. Results are
/// cached per query, and nothing is written to the files themselves.
final class MetadataEnrichmentService: @unchecked Sendable {
    static let shared = MetadataEnrichmentService()

    private let providers: [any TrackMetadataProvider]
    private let artworkSession: URLSession
    private let lock = NSLock()
    private var cache: [String: [TrackEnrichment]] = [:]
    private let cacheLimit = 400

    init(
        providers: [any TrackMetadataProvider]? = nil,
        artworkSession: URLSession = MetadataHTTP.session()
    ) {
        self.providers = providers ?? [
            AppleMusicMetadataProvider(),
            DeezerMetadataProvider(),
        ]
        self.artworkSession = artworkSession
    }

    // MARK: - Covers for albums and artists

    /// Album covers from the iTunes album index, which knows the release better
    /// than a song search and returns a proper collection artwork.
    func albumArtworkCandidates(title: String, artist: String?) async -> [TrackEnrichment] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return [] }
        let terms = [artist, title]
            .compactMap { LocalTrack.trimmed($0) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: terms.joined(separator: " ")),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components?.url,
              let json = await MetadataHTTP.json(url, session: artworkSession) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return [] }

        let found = results.compactMap { item -> TrackEnrichment? in
            guard let collection = LocalTrack.trimmed(item["collectionName"] as? String) else {
                return nil
            }
            let artwork = LocalTrack.trimmed(item["artworkUrl100"] as? String)?
                .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            guard artwork != nil else { return nil }
            return TrackEnrichment(
                title: collection,
                artist: LocalTrack.trimmed(item["artistName"] as? String),
                album: collection,
                year: MetadataHTTP.year(from: item["releaseDate"] as? String),
                artworkURL: artwork,
                source: "Apple Music"
            )
        }
        return Self.uniqueArtwork(found)
    }

    /// Artist portraits from Deezer's artist index. Falls back to album covers
    /// in `MusicLibrary.artworkCandidates(for:)` when no portrait is found.
    func artistArtworkCandidates(name: String) async -> [TrackEnrichment] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.deezer.com/search/artist")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmedName),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components?.url,
              let json = await MetadataHTTP.json(url, session: artworkSession) as? [String: Any],
              let results = json["data"] as? [[String: Any]]
        else { return [] }

        let found = results.compactMap { item -> TrackEnrichment? in
            guard let artistName = LocalTrack.trimmed(item["name"] as? String) else { return nil }
            let artwork = LocalTrack.trimmed(item["picture_xl"] as? String)
                ?? LocalTrack.trimmed(item["picture_big"] as? String)
            guard artwork != nil else { return nil }
            return TrackEnrichment(
                title: artistName,
                artist: artistName,
                artworkURL: artwork,
                source: "Deezer"
            )
        }
        return Self.uniqueArtwork(found)
    }

    private static func uniqueArtwork(_ values: [TrackEnrichment]) -> [TrackEnrichment] {
        var seen: Set<String> = []
        return values.filter { value in
            guard let artwork = value.artworkURL else { return false }
            return seen.insert(artwork).inserted
        }
    }

    func bestMatch(for track: LocalTrack) async -> TrackEnrichment? {
        let all = await candidates(for: track)
        return all.first { $0.matchScore >= TrackMatch.acceptThreshold }
    }

    func candidates(for track: LocalTrack) async -> [TrackEnrichment] {
        await candidates(
            title: track.displayTitle,
            artist: track.displayArtist,
            album: track.displayAlbum
        )
    }

    func candidates(
        title: String,
        artist: String?,
        album: String?
    ) async -> [TrackEnrichment] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return [] }
        let query = TrackQuery(
            title: trimmedTitle,
            artist: LocalTrack.trimmed(artist),
            album: LocalTrack.trimmed(album)
        )
        if let cached = cached(query.key) { return cached }

        // Both catalogues are public and independent: ask them in parallel.
        let found: [TrackEnrichment] = await withTaskGroup(
            of: [TrackEnrichment].self,
            returning: [TrackEnrichment].self
        ) { group in
            for provider in providers {
                group.addTask { await provider.search(query) }
            }
            var all: [TrackEnrichment] = []
            for await part in group { all.append(contentsOf: part) }
            return all
        }

        let scored = found.compactMap { candidate -> TrackEnrichment? in
            guard !candidate.isEmpty else { return nil }
            var copy = candidate
            copy.matchScore = TrackMatch.score(query: query, candidate: candidate)
            return copy.matchScore > 0.2 ? copy : nil
        }
        let deduped = Self.deduplicate(scored)
        store(deduped, for: query.key)
        return deduped
    }

    // MARK: - Cache

    private func cached(_ key: String) -> [TrackEnrichment]? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    private func store(_ value: [TrackEnrichment], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if cache.count >= cacheLimit, let first = cache.keys.first {
            cache.removeValue(forKey: first)
        }
        cache[key] = value
    }

    static func deduplicate(_ values: [TrackEnrichment]) -> [TrackEnrichment] {
        var best: [String: TrackEnrichment] = [:]
        var order: [String] = []
        for value in values {
            let key = [
                TrackMatch.normalised(value.title ?? ""),
                TrackMatch.normalised(value.artist ?? ""),
                TrackMatch.normalised(value.album ?? ""),
            ].joined(separator: "|")
            if let existing = best[key] {
                if value.matchScore > existing.matchScore
                    || (value.matchScore == existing.matchScore && existing.artworkURL == nil) {
                    best[key] = value
                }
            } else {
                best[key] = value
                order.append(key)
            }
        }
        return order
            .compactMap { best[$0] }
            .sorted {
                if abs($0.matchScore - $1.matchScore) > 0.001 {
                    return $0.matchScore > $1.matchScore
                }
                if $0.completeness != $1.completeness {
                    return $0.completeness > $1.completeness
                }
                return ($0.artworkURL?.isEmpty == false) && ($1.artworkURL?.isEmpty != false)
            }
    }
}
