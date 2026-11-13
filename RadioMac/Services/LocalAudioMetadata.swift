@preconcurrency import AVFoundation
import Foundation

/// Metadata read from an audio file's tags. Nothing is written back to the file.
struct AudioFileMetadata: Equatable, Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var genre: String?
    var year: Int?
    var trackNumber: Int?
    var duration: TimeInterval?
    var artworkData: Data?
    /// AVFoundation can decode the file (guards against mislabelled files).
    var playable: Bool = true
}

/// Reads tags and embedded artwork through AVFoundation, and keeps the cached
/// artwork inside the app container.
enum LocalAudioMetadata {
    /// Formats AVFoundation plays reliably on macOS 14+.
    static var supportedExtensions: Set<String> { AudioFileTypes.supportedExtensions }

    static let maxArtworkBytes = 12 * 1024 * 1024

    static func isSupported(_ url: URL) -> Bool {
        AudioFileTypes.isSupported(url)
    }

    static func isPlaylistFile(_ url: URL) -> Bool {
        ["m3u", "m3u8"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Tags

    static func read(at url: URL) async -> AudioFileMetadata {
        var result = AudioFileMetadata()
        let asset = AVURLAsset(url: url)
        result.playable = (try? await asset.load(.isPlayable)) ?? true

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                result.duration = seconds
            }
        }

        var items: [AVMetadataItem] = []
        if let common = try? await asset.load(.commonMetadata) {
            items.append(contentsOf: common)
        }
        if let specific = try? await asset.load(.metadata) {
            items.append(contentsOf: specific)
        }

        for item in items {
            switch classify(item) {
            case .title:
                if result.title == nil {
                    result.title = try? await item.load(.stringValue)
                }
            case .artist:
                if result.artist == nil {
                    result.artist = try? await item.load(.stringValue)
                }
            case .album:
                if result.album == nil {
                    result.album = try? await item.load(.stringValue)
                }
            case .genre:
                if result.genre == nil, let raw = try? await item.load(.stringValue) {
                    result.genre = sanitizedGenre(raw)
                }
            case .year:
                if result.year == nil, let raw = try? await item.load(.stringValue) {
                    result.year = year(from: raw)
                }
            case .trackNumber:
                if result.trackNumber == nil {
                    result.trackNumber = await trackNumber(from: item)
                }
            case .artwork:
                if result.artworkData == nil, let data = try? await item.load(.dataValue) {
                    result.artworkData = data.count <= maxArtworkBytes ? data : nil
                }
            case .other:
                break
            }
        }

        result.title = LocalTrack.trimmed(result.title)
        result.artist = LocalTrack.trimmed(result.artist)
        result.album = LocalTrack.trimmed(result.album)
        result.genre = LocalTrack.trimmed(result.genre)
        result.year = LocalTrack.validYear(result.year)
        return result
    }

    private enum TagKind {
        case title
        case artist
        case album
        case genre
        case year
        case trackNumber
        case artwork
        case other
    }

    private static func classify(_ item: AVMetadataItem) -> TagKind {
        guard let identifier = item.identifier else {
            // Fallback for containers that expose only a common key.
            guard let key = item.commonKey else { return .other }
            switch key {
            case .commonKeyTitle: return .title
            case .commonKeyArtist: return .artist
            case .commonKeyAlbumName: return .album
            case .commonKeyType: return .genre
            case .commonKeyArtwork: return .artwork
            default: return .other
            }
        }

        switch identifier {
        case .commonIdentifierTitle, .iTunesMetadataSongName, .id3MetadataTitleDescription:
            return .title
        case .commonIdentifierArtist, .iTunesMetadataArtist, .id3MetadataOriginalArtist,
             .iTunesMetadataAlbumArtist:
            return .artist
        case .commonIdentifierAlbumName, .iTunesMetadataAlbum, .id3MetadataAlbumTitle:
            return .album
        case .commonIdentifierType, .iTunesMetadataPredefinedGenre, .iTunesMetadataUserGenre,
             .id3MetadataContentType:
            return .genre
        case .commonIdentifierArtwork, .iTunesMetadataCoverArt, .id3MetadataAttachedPicture:
            return .artwork
        case .iTunesMetadataReleaseDate, .id3MetadataYear, .id3MetadataRecordingTime,
             .id3MetadataReleaseTime, .id3MetadataOriginalReleaseYear, .id3MetadataDate:
            return .year
        case .iTunesMetadataTrackNumber, .id3MetadataTrackNumber:
            return .trackNumber
        default:
            return .other
        }
    }

    private static func trackNumber(from item: AVMetadataItem) async -> Int? {
        if let number = try? await item.load(.numberValue), number.intValue > 0 {
            return number.intValue
        }
        if let raw = try? await item.load(.stringValue) {
            return trackNumber(from: raw)
        }
        return nil
    }

    static func trackNumber(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let numberPart = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        guard let value = Int(numberPart), value > 0, value < 1000 else { return nil }
        return value
    }

    static func year(from raw: String) -> Int? {
        let characters = Array(raw)
        guard characters.count >= 4 else { return nil }
        for start in 0...(characters.count - 4) {
            let slice = String(characters[start..<(start + 4)])
            guard slice.allSatisfy(\.isNumber), let value = Int(slice),
                  (1500...2999).contains(value)
            else { continue }
            let previousIsDigit = start > 0 && characters[start - 1].isNumber
            let nextIsDigit = start + 4 < characters.count && characters[start + 4].isNumber
            guard !previousIsDigit, !nextIsDigit else { continue }
            return value
        }
        return nil
    }

    /// ID3 numeric genre codes like `(17)` are noise; drop them.
    private static func sanitizedGenre(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")"),
           Int(trimmed.dropFirst().dropLast()) != nil {
            return nil
        }
        return LocalTrack.trimmed(trimmed)
    }

    // MARK: - Fallbacks from the file name

    /// `01 - Artist - Title.mp3` → artist and title, `02. Song.m4a` → title.
    static func fallback(from url: URL) -> (title: String, artist: String?) {
        let raw = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = stripTrackPrefix(raw)

        let parts = name
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            let artist = parts[0]
            let title = parts.dropFirst().joined(separator: " - ")
            return (title, artist)
        }
        return (name, nil)
    }

    /// Drops a leading track number: `01 - Song`, `02. Song`, `3) Song`.
    static func stripTrackPrefix(_ raw: String) -> String {
        let trimmed = raw.drop(while: { $0 == " " || $0 == "\t" })
        var digits = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber, digits < 3 {
            digits += 1
            index = trimmed.index(after: index)
        }
        guard digits > 0, index < trimmed.endIndex else { return String(trimmed) }

        let rest = trimmed[index...]
        for separator in [" - ", " . ", ". ", ") ", " ) ", "- ", ".", ") ", " "] {
            guard rest.hasPrefix(separator) else { continue }
            let stripped = rest.dropFirst(separator.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? String(trimmed) : stripped
        }
        return String(trimmed)
    }
}

/// Cached embedded artwork, written to the app's caches directory.
enum MusicArtworkStore {
    static var directory: URL {
        #if os(iOS)
        // Documents survives development re-installs together with the audio
        // files; Application Support was rolled back by some installs.
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #else
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #endif
        return base
            .appendingPathComponent("RadioMac", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
    }

    #if os(iOS)
    /// Previous cover location, migrated into Documents on launch.
    static var legacyDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("RadioMac", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
    }
    #endif

    @discardableResult
    static func save(_ data: Data, for trackID: String, in folder: URL = directory) -> String? {
        guard !data.isEmpty else { return nil }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(trackID).jpg")
            try data.write(to: file, options: .atomic)
            return file.absoluteString
        } catch {
            return nil
        }
    }

    static func remove(for trackID: String, in folder: URL = directory) {
        let file = folder.appendingPathComponent("\(trackID).jpg")
        try? FileManager.default.removeItem(at: file)
    }
}
