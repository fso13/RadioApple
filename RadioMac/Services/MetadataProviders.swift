import Foundation

/// Apple's public iTunes Search API: no key, covers at 600×600, album, year and
/// a broad genre. It already powers radio artwork in this app.
struct AppleMusicMetadataProvider: TrackMetadataProvider {
    let name = "Apple Music"

    private let session: URLSession

    init(session: URLSession = MetadataHTTP.session()) {
        self.session = session
    }

    func search(_ query: TrackQuery) async -> [TrackEnrichment] {
        let terms = [query.artist, query.title]
            .compactMap { LocalTrack.trimmed($0) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: terms.joined(separator: " ")),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components?.url,
              let json = await MetadataHTTP.json(url, session: session) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { item in
            guard let title = LocalTrack.trimmed(item["trackName"] as? String) else { return nil }
            let artwork = LocalTrack.trimmed(item["artworkUrl100"] as? String)?
                .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            return TrackEnrichment(
                title: title,
                artist: LocalTrack.trimmed(item["artistName"] as? String),
                album: LocalTrack.trimmed(item["collectionName"] as? String),
                year: MetadataHTTP.year(from: item["releaseDate"] as? String),
                genre: LocalTrack.trimmed(item["primaryGenreName"] as? String),
                artworkURL: artwork,
                source: name
            )
        }
    }
}

/// Deezer's public search API: no key, large covers, and decent coverage of
/// releases the iTunes store does not carry.
struct DeezerMetadataProvider: TrackMetadataProvider {
    let name = "Deezer"

    private let session: URLSession

    init(session: URLSession = MetadataHTTP.session()) {
        self.session = session
    }

    func search(_ query: TrackQuery) async -> [TrackEnrichment] {
        let terms = [query.artist, query.title]
            .compactMap { LocalTrack.trimmed($0) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        var components = URLComponents(string: "https://api.deezer.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: terms.joined(separator: " ")),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components?.url,
              let json = await MetadataHTTP.json(url, session: session) as? [String: Any],
              let results = json["data"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { item in
            guard let title = LocalTrack.trimmed(item["title"] as? String) else { return nil }
            let artist = (item["artist"] as? [String: Any])?["name"] as? String
            let albumInfo = item["album"] as? [String: Any]
            let album = albumInfo?["title"] as? String
            let cover = LocalTrack.trimmed(albumInfo?["cover_xl"] as? String)
                ?? LocalTrack.trimmed(albumInfo?["cover_big"] as? String)
            return TrackEnrichment(
                title: title,
                artist: LocalTrack.trimmed(artist),
                album: LocalTrack.trimmed(album),
                genre: nil,
                artworkURL: cover,
                source: name
            )
        }
    }
}

enum MetadataHTTP {
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 16
        configuration.httpAdditionalHeaders = ["User-Agent": "RadioMac/1.4 (macOS)"]
        return URLSession(configuration: configuration)
    }

    static func json(_ url: URL, session: URLSession) async -> Any? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    static func year(from raw: String?) -> Int? {
        guard let raw, raw.count >= 4,
              let value = Int(raw.prefix(4)),
              (1500...2999).contains(value)
        else { return nil }
        return value
    }
}
