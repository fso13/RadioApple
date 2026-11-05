import Foundation

/// Audio containers AVFoundation plays reliably on macOS 14+ and iOS 17+.
///
/// The list lives in the shared support layer so the library and the Finder
/// extension offer exactly the same files: the context menu must not appear for
/// formats the app cannot import.
enum AudioFileTypes {
    static let supportedExtensions: Set<String> = [
        "mp3", "mp2", "mp1",
        "m4a", "m4b", "m4r", "aac", "alac",
        "flac", "wav", "wave", "aif", "aiff", "aifc", "caf",
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
