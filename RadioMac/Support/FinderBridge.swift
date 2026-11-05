import Foundation

/// What the Finder context menu offers for the current selection.
///
/// The values are shared by the Finder Sync extension and the app; they are
/// stored as raw strings so a future change stays readable in old payloads.
enum FinderAction: String, Codable, Sendable {
    /// Play the selected audio files in RadioMac.
    case playAudio
    /// Turn the selected folder into a playlist.
    case createPlaylist

    /// Localization key of the menu title. The extension has no strings of its
    /// own and reads the title from the app's catalog.
    var menuTitleKey: String {
        switch self {
        case .playAudio: return "Проиграть в RadioMac"
        case .createPlaylist: return "Создать плейлист в RadioMac"
        }
    }
}

/// The single menu entry the Finder should show, and the items it applies to.
struct FinderSelection: Equatable, Sendable {
    let action: FinderAction
    let urls: [URL]
}

/// Decides what the Finder menu offers for a selection.
///
/// The rule is deliberately pure — no AppKit, no file contents — so the
/// extension's behaviour can be unit tested from the app target.
enum FinderMenuPlanner {
    static func plan(for urls: [URL]) -> FinderSelection? {
        let items = urls.filter(\.isFileURL)
        guard !items.isEmpty else { return nil }

        // A single folder becomes a playlist; several folders would need
        // several playlists, so the menu stays out of that case.
        if items.count == 1, isFolder(items[0]) {
            return FinderSelection(action: .createPlaylist, urls: items)
        }

        // Everything else must be an audio file the library understands.
        guard items.allSatisfy(isAudioFile) else { return nil }
        return FinderSelection(action: .playAudio, urls: items)
    }

    static func isFolder(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return true
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    static func isAudioFile(_ url: URL) -> Bool {
        !isFolder(url) && AudioFileTypes.isSupported(url)
    }
}

/// Payload handed to the app when Launch Services cannot deliver the items
/// itself. The app opens the same items with the same actions.
struct FinderRequest: Codable, Equatable, Sendable {
    var action: FinderAction
    var paths: [String]
}

/// Distributed-notification channel between the extension and the app.
///
/// Launch Services is the primary route: opening the items with RadioMac also
/// grants the sandboxed app read access to them. The notification is the
/// fallback for a refused launch, when the app is already running.
enum FinderBridge {
    static let notificationName = Notification.Name("com.fso13.radioMac.finderRequest")
    static let requestKey = "request"

    static func post(_ request: FinderRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: [requestKey: data],
            deliverImmediately: true
        )
    }

    static func request(from userInfo: [AnyHashable: Any]?) -> FinderRequest? {
        guard let data = userInfo?[requestKey] as? Data else { return nil }
        return try? JSONDecoder().decode(FinderRequest.self, from: data)
    }
}
