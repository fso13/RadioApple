import Foundation

/// Track metadata shown in the now-playing bar, menu bar and Control Center.
struct NowPlaying: Equatable, Sendable {
    var raw: String
    var artist: String?
    var title: String?
    var album: String?
    var artworkURL: String?

    var hasArtwork: Bool {
        guard let artworkURL else { return false }
        return !artworkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayTitle: String {
        let song = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let song, !song.isEmpty { return song }
        return raw
    }

    var displayArtist: String? {
        let value = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// `Artist — Title` for the menu bar, title alone when there is no artist.
    var trayLine: String {
        if let who = displayArtist {
            return "\(who) — \(displayTitle)"
        }
        return displayTitle
    }
}

/// Parses ICY/Shoutcast metadata into artist/title pairs.
enum NowPlayingParser {
    private static let streamTitle = try! NSRegularExpression(
        pattern: "StreamTitle='(.*?)';",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let dashSplit = try! NSRegularExpression(pattern: "\\s+[-–—]\\s+")
    private static let whitespace = try! NSRegularExpression(pattern: "\\s+")

    private static let junk: Set<String> = [
        "-", "—", "–", "n/a", "na", "null", "unknown", "undefined",
        "advert", "advertisement", "реклама",
    ]

    static func unwrapICYBlock(_ raw: String) -> String? {
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        if let match = streamTitle.firstMatch(in: raw, options: [], range: range),
           let group = Range(match.range(at: 1), in: raw) {
            return raw[group].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parse(_ raw: String, stationName: String? = nil) -> NowPlaying? {
        guard let unwrapped = unwrapICYBlock(raw) else { return nil }

        let cleaned = collapseWhitespace(unwrapped)
        guard !cleaned.isEmpty, cleaned.count <= 240 else { return nil }
        guard !junk.contains(cleaned.lowercased()) else { return nil }
        if let stationName {
            let name = stationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, cleaned.lowercased() == name.lowercased() {
                return nil
            }
        }
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
            return nil
        }

        let parts = splitOnDashes(cleaned)
        if parts.count >= 2 {
            let artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = parts.dropFirst()
                .joined(separator: " — ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if artist.isEmpty || title.isEmpty {
                return NowPlaying(raw: cleaned, title: cleaned)
            }
            return NowPlaying(raw: cleaned, artist: artist, title: title)
        }
        return NowPlaying(raw: cleaned, title: cleaned)
    }

    static func looksLikeImageURL(_ url: String?) -> Bool {
        guard let url, let parsed = URL(string: url) else { return false }
        let path = parsed.path.lowercased()
        return [".jpg", ".jpeg", ".png", ".webp", ".gif"].contains { path.hasSuffix($0) }
    }

    // MARK: - Helpers

    private static func collapseWhitespace(_ value: String) -> String {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let collapsed = whitespace.stringByReplacingMatches(
            in: value, options: [], range: range, withTemplate: " "
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitOnDashes(_ value: String) -> [String] {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = dashSplit.matches(in: value, options: [], range: range)
        guard !matches.isEmpty else { return [value] }

        var parts: [String] = []
        var cursor = value.startIndex
        for match in matches {
            guard let separator = Range(match.range, in: value) else { continue }
            parts.append(String(value[cursor..<separator.lowerBound]))
            cursor = separator.upperBound
        }
        parts.append(String(value[cursor...]))
        return parts
    }
}
