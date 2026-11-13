import AppKit
import Foundation

/// One track read from the macOS Music app library.
struct MacMusicTrack: Sendable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let genre: String?
    let duration: TimeInterval?
    let location: URL?
}

/// One user playlist from the macOS Music app.
struct MacMusicPlaylist: Sendable {
    let name: String
    let trackIDs: [String]
}

enum MacMusicLibraryError: LocalizedError, Sendable {
    case automationDenied
    case musicNotRunning
    case scriptFailed(String)
    case noTracks

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            return "Нет доступа к приложению «Музыка». Разрешите управление в "
                + "Системные настройки → Конфиденциальность и безопасность → Автоматизация."
        case .musicNotRunning:
            return "Приложение «Музыка» не запущено. Откройте его и повторите импорт."
        case .scriptFailed(let message):
            return "Не удалось прочитать медиатеку «Музыка»: \(message)"
        case .noTracks:
            return "В медиатеке «Музыка» не найдено локальных треков."
        }
    }
}

/// Reads the user's local Music.app library through AppleScript.
///
/// Music.app has no public media-library API on macOS; AppleScript is the only
/// supported way to get track locations and user playlists. Cloud and
/// DRM-protected items come back without a usable `location` and are skipped.
enum MacMusicLibraryService {
    nonisolated static func load() throws -> (tracks: [MacMusicTrack], playlists: [MacMusicPlaylist]) {
        let tracksRaw = try run(tracksScript)
        let playlistsRaw = try run(playlistsScript)
        return (parseTracks(tracksRaw), parsePlaylists(playlistsRaw))
    }

    private static func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw MacMusicLibraryError.scriptFailed("не удалось создать AppleScript")
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
            if code == -1743 { throw MacMusicLibraryError.automationDenied }
            if code == -600 { throw MacMusicLibraryError.musicNotRunning }
            let message = (error["NSAppleScriptErrorBriefMessage"] as? String)
                ?? (error["NSAppleScriptErrorMessage"] as? String)
                ?? "код \(code)"
            throw MacMusicLibraryError.scriptFailed(message)
        }
        return result.stringValue ?? ""
    }

    private static func parseTracks(_ raw: String) -> [MacMusicTrack] {
        raw.split(separator: "\u{1E}", omittingEmptySubsequences: true).compactMap { row in
            let fields = row.split(
                separator: "\u{1F}",
                omittingEmptySubsequences: false
            ).map(String.init)
            guard fields.count >= 7, !fields[0].isEmpty else { return nil }

            let duration = Double(fields[5].replacingOccurrences(of: ",", with: "."))
            let location = fields[6].isEmpty
                ? nil
                : URL(fileURLWithPath: fields[6])

            return MacMusicTrack(
                id: fields[0],
                title: fields[1],
                artist: nonEmpty(fields[2]),
                album: nonEmpty(fields[3]),
                genre: nonEmpty(fields[4]),
                duration: duration,
                location: location
            )
        }
    }

    private static func parsePlaylists(_ raw: String) -> [MacMusicPlaylist] {
        raw.split(separator: "\u{1E}", omittingEmptySubsequences: true).compactMap { row in
            let fields = row.split(
                separator: "\u{1F}",
                omittingEmptySubsequences: false
            ).map(String.init)
            guard fields.count >= 2 else { return nil }
            let name = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            var seen: Set<String> = []
            let trackIDs = fields.dropFirst().filter {
                !$0.isEmpty && seen.insert($0).inserted
            }
            return MacMusicPlaylist(name: name, trackIDs: trackIDs)
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let tracksScript = """
    if application "Music" is not running then
        launch application "Music"
        delay 1
    end if
    set fs to (ASCII character 31)
    set rs to (ASCII character 30)
    set out to ""
    tell application "Music"
        set lib to library playlist 1
        repeat with t in (every track of lib)
            set tid to ""
            set tname to ""
            set tartist to ""
            set talbum to ""
            set tgenre to ""
            set tdur to ""
            set tpath to ""
            try
                set tid to (persistent ID of t) as text
            end try
            try
                set tname to (name of t) as text
            end try
            try
                set tartist to (artist of t) as text
            end try
            try
                set talbum to (album of t) as text
            end try
            try
                set tgenre to (genre of t) as text
            end try
            try
                set tdur to (duration of t) as text
            end try
            try
                set tpath to POSIX path of (location of t as alias)
            end try
            set out to out & tid & fs & tname & fs & tartist & fs & talbum & fs & tgenre & fs & tdur & fs & tpath & rs
        end repeat
    end tell
    return out
    """

    private static let playlistsScript = """
    if application "Music" is not running then
        launch application "Music"
        delay 1
    end if
    set fs to (ASCII character 31)
    set rs to (ASCII character 30)
    set out to ""
    tell application "Music"
        repeat with p in (every user playlist)
            set pname to ""
            try
                set pname to (name of p) as text
            end try
            set out to out & pname & fs
            repeat with t in (every track of p)
                set tid to ""
                try
                    set tid to (persistent ID of t) as text
                end try
                set out to out & tid & fs
            end repeat
            set out to out & rs
        end repeat
    end tell
    return out
    """
}
