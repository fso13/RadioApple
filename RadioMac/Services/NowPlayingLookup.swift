import Foundation

/// Resolves the current track from station APIs (SomaFM, Radio Paradise),
/// an Icecast status page, or in-band ICY metadata.
final class NowPlayingLookup {
    static let shared = NowPlayingLookup()

    private static let userAgent = "RadioMac/1.0"
    private let timeout: TimeInterval = 8
    private let session: URLSession

    private var artworkCache: [String: String?] = [:]
    private let cacheLock = NSLock()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Track

    func resolve(
        streamURL: String,
        stationName: String?,
        allowICY: Bool = true
    ) async -> NowPlaying? {
        guard let url = URL(string: streamURL),
              let host = url.host, !host.isEmpty
        else { return nil }

        if let paradise = await radioParadise(url) { return paradise }
        if let soma = await somaFM(url) { return soma }
        if let icecast = await icecastStatus(url, stationName: stationName) { return icecast }

        guard allowICY, !Self.looksLikePlaylist(url) else { return nil }
        return await icySidecar(url, stationName: stationName)
    }

    // MARK: - Artwork

    func artworkFor(_ track: NowPlaying) async -> String? {
        if track.hasArtwork { return track.artworkURL }
        let song = track.displayTitle
        guard song.count >= 3 else { return nil }
        let query = [track.displayArtist, song].compactMap { $0 }.joined(separator: " ")
        guard !query.isEmpty else { return nil }

        if let cached = cachedArtwork(for: query) {
            return cached
        }

        let url = await iTunesArtwork(query)
        storeArtwork(url, for: query)
        return url
    }

    private func cachedArtwork(for query: String) -> String? {
        cacheLock.withLock { artworkCache[query] } ?? nil
    }

    private func storeArtwork(_ url: String?, for query: String) {
        cacheLock.withLock {
            artworkCache[query] = url
            if artworkCache.count > 80, let first = artworkCache.keys.first {
                artworkCache.removeValue(forKey: first)
            }
        }
    }

    // MARK: - Radio Paradise

    private func radioParadise(_ stream: URL) async -> NowPlaying? {
        guard let host = stream.host, host.contains("radioparadise.com") else { return nil }
        let path = stream.path.lowercased()
        var channel = 0
        if path.contains("mellow") {
            channel = 1
        } else if path.contains("rock") {
            channel = 2
        } else if path.contains("global") || path.contains("world") {
            channel = 3
        }

        guard let url = URL(string: "https://api.radioparadise.com/api/nowplaying_list?chan=\(channel)"),
              let json = await getJSON(url) as? [String: Any],
              let songs = json["song"] as? [String: Any],
              let song = songs["0"] as? [String: Any]
        else { return nil }

        guard let title = (song["title"] as? String)?.trimmed, !title.isEmpty else { return nil }
        let artist = (song["artist"] as? String)?.trimmed
        let cover = (song["cover"] as? String)?.trimmed
        let artwork = (cover?.isEmpty == false) ? "https://img.radioparadise.com/\(cover!)" : nil
        let raw = [artist, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")

        return NowPlaying(
            raw: raw,
            artist: artist,
            title: title,
            album: (song["album"] as? String)?.trimmed,
            artworkURL: artwork
        )
    }

    // MARK: - SomaFM

    private func somaFM(_ stream: URL) async -> NowPlaying? {
        guard let host = stream.host, host.contains("somafm.com") else { return nil }
        let segments = stream.pathComponents.filter { $0 != "/" }
        guard let first = segments.first, !first.isEmpty else { return nil }
        let channel = first.components(separatedBy: "-").first ?? ""
        guard !channel.isEmpty else { return nil }

        guard let url = URL(string: "https://somafm.com/songs/\(channel).json"),
              let json = await getJSON(url) as? [String: Any],
              let songs = json["songs"] as? [[String: Any]],
              let song = songs.first
        else { return nil }

        guard let title = (song["title"] as? String)?.trimmed, !title.isEmpty else { return nil }
        let artist = (song["artist"] as? String)?.trimmed
        let art = (song["albumArt"] as? String)?.trimmed
        let raw = [artist, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")

        return NowPlaying(
            raw: raw,
            artist: artist,
            title: title,
            album: (song["album"] as? String)?.trimmed,
            artworkURL: (art?.hasPrefix("http") == true) ? art : nil
        )
    }

    // MARK: - Icecast status

    private func icecastStatus(_ stream: URL, stationName: String?) async -> NowPlaying? {
        guard let scheme = stream.scheme, let host = stream.host else { return nil }
        let origin: String
        if let port = stream.port {
            origin = "\(scheme)://\(host):\(port)"
        } else {
            origin = "\(scheme)://\(host)"
        }
        guard let url = URL(string: "\(origin)/status-json.xsl"),
              let json = await getJSON(url) as? [String: Any],
              let stats = json["icestats"] as? [String: Any]
        else { return nil }

        var sources: [[String: Any]] = []
        if let single = stats["source"] as? [String: Any] {
            sources = [single]
        } else if let list = stats["source"] as? [[String: Any]] {
            sources = list
        }
        guard !sources.isEmpty else { return nil }

        let mount = stream.path
        var matched: [String: Any]?
        if !mount.isEmpty {
            matched = sources.first { source in
                let listen = source["listenurl"] as? String ?? ""
                return listen.contains(mount)
            }
        }
        if matched == nil, sources.count == 1 { matched = sources.first }
        guard let source = matched else { return nil }

        let title = (source["title"] as? String) ?? (source["yp_currently_playing"] as? String)
        guard let title else { return nil }
        return NowPlayingParser.parse(title, stationName: stationName)
    }

    // MARK: - ICY sidecar probe

    private func icySidecar(_ stream: URL, stationName: String?) async -> NowPlaying? {
        var request = URLRequest(url: stream)
        request.timeoutInterval = timeout
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        let probeSession = URLSession(configuration: configuration)
        defer { probeSession.finishTasksAndInvalidate() }

        do {
            let (bytes, response) = try await probeSession.bytes(for: request)
            let metaInt = Int((response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "icy-metaint") ?? "") ?? 0
            guard metaInt > 0, metaInt <= 256_000 else { return nil }

            let needed = metaInt * 4 + 1 + 255 * 16
            let deadline = Date().addingTimeInterval(timeout)
            var buffer = Data()
            buffer.reserveCapacity(needed)

            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= needed || Date() > deadline { break }
            }

            return parseICYBlocks(Array(buffer), metaInt: metaInt, stationName: stationName)
        } catch {
            return nil
        }
    }

    private func parseICYBlocks(_ bytes: [UInt8], metaInt: Int, stationName: String?) -> NowPlaying? {
        var offset = 0
        for _ in 0..<4 {
            let metaAt = offset + metaInt
            guard bytes.count > metaAt else { break }
            let metaLength = Int(bytes[metaAt]) * 16
            offset = metaAt + 1
            if metaLength == 0 { continue }
            guard bytes.count >= offset + metaLength else { break }
            let block = String(
                decoding: bytes[offset..<(offset + metaLength)],
                as: UTF8.self
            )
            if let parsed = NowPlayingParser.parse(block, stationName: stationName) {
                return parsed
            }
            offset += metaLength
        }
        return nil
    }

    // MARK: - iTunes artwork search

    private func iTunesArtwork(_ query: String) async -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url,
              let json = await getJSON(url) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let raw = results.first?["artworkUrl100"] as? String,
              !raw.isEmpty
        else { return nil }
        return raw.replacingOccurrences(of: "100x100bb", with: "300x300bb")
    }

    // MARK: - Helpers

    private func getJSON(_ url: URL) async -> Any? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    private static func looksLikePlaylist(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".m3u8") || path.hasSuffix(".m3u")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
