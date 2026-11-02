import Foundation

/// One line of an M3U playlist: where the audio lives plus optional `#EXTINF`
/// display data.
struct M3UEntry: Equatable, Sendable {
    var location: String
    var title: String?
    var artist: String?
    var duration: TimeInterval?
}

struct M3UParsedPlaylist: Equatable, Sendable {
    var name: String?
    var entries: [M3UEntry]

    var isEmpty: Bool { entries.isEmpty }
}

/// Reads and writes M3U/M3U8 playlists that point at local audio files.
///
/// Both absolute paths and paths relative to the playlist file are supported;
/// `file://` URLs work too. Stream URLs are ignored — those belong to the radio
/// library and are imported through *Импорт/экспорт*.
enum MusicPlaylistFile {
    static let fileExtensions = ["m3u", "m3u8"]

    // MARK: - Parsing

    static func parse(_ data: Data) -> M3UParsedPlaylist {
        parse(text: decode(data))
    }

    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .windowsCP1251) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(text input: String) -> M3UParsedPlaylist {
        var playlist = M3UParsedPlaylist(entries: [])
        var pendingTitle: String?
        var pendingArtist: String?
        var pendingDuration: TimeInterval?

        for rawLine in input.components(separatedBy: .newlines) {
            let line = rawLine
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let upper = line.uppercased()

            if upper.hasPrefix("#EXTM3U") { continue }

            if upper.hasPrefix("#PLAYLIST:") {
                let name = String(line.dropFirst("#PLAYLIST:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { playlist.name = name }
                continue
            }

            if upper.hasPrefix("#EXTINF:") {
                let payload = String(line.dropFirst("#EXTINF:".count))
                let parts = payload.split(
                    separator: ",",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                pendingDuration = duration(fromHeader: String(parts[0]))
                if parts.count > 1 {
                    let display = String(parts[1])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let split = splitDisplay(display)
                    pendingTitle = split.title
                    pendingArtist = split.artist
                }
                continue
            }

            // Other `#EXT…` directives (#EXTGRP, #EXTVLCOPT, …) are ignored.
            guard !line.hasPrefix("#") else { continue }

            playlist.entries.append(
                M3UEntry(
                    location: line,
                    title: pendingTitle,
                    artist: pendingArtist,
                    duration: pendingDuration
                )
            )
            pendingTitle = nil
            pendingArtist = nil
            pendingDuration = nil
        }

        return playlist
    }

    /// `#EXTINF:213,Artist - Title` → `213`; `-1` means "unknown" and becomes nil.
    static func duration(fromHeader header: String) -> TimeInterval? {
        let first = header.split(separator: " ", maxSplits: 1).first.map(String.init) ?? header
        guard let value = Double(first.trimmingCharacters(in: .whitespaces)),
              value.isFinite,
              value > 0
        else { return nil }
        return value
    }

    static func splitDisplay(_ display: String) -> (artist: String?, title: String?) {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        guard let range = trimmed.range(of: " - ") else {
            return (nil, trimmed)
        }
        let artist = String(trimmed[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(trimmed[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (artist.isEmpty ? nil : artist, title.isEmpty ? nil : title)
    }

    // MARK: - Resolving

    /// Turns a playlist line into a local file URL. Returns `nil` for stream
    /// URLs and for Windows paths, which macOS cannot open.
    static func resolvedURL(for location: String, relativeTo playlist: URL) -> URL? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let remotePrefixes = ["http://", "https://", "rtmp://", "rtsp://", "mms://", "icy://"]
        guard !remotePrefixes.contains(where: { lower.hasPrefix($0) }) else { return nil }

        if lower.hasPrefix("file://") {
            guard let url = URL(string: trimmed), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        // "C:\Music\song.mp3" and UNC shares cannot be opened on macOS.
        if trimmed.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil {
            return nil
        }
        if trimmed.hasPrefix("\\\\") { return nil }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let base = playlist.deletingLastPathComponent()
        return base
            .appendingPathComponent(decoded)
            .standardizedFileURL
    }

    // MARK: - Export

    static func export(name: String, tracks: [LocalTrack]) -> String {
        var lines = ["#EXTM3U"]
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            lines.append("#PLAYLIST:\(trimmedName)")
        }
        for track in tracks {
            let seconds = Int((track.duration ?? -1).rounded())
            let display = [track.displayArtist, track.displayTitle]
                .compactMap { $0 }
                .joined(separator: " - ")
            lines.append("#EXTINF:\(seconds),\(display)")
            lines.append(track.path)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func exportData(name: String, tracks: [LocalTrack]) -> Data {
        Data(export(name: name, tracks: tracks).utf8)
    }
}
