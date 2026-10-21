import Foundation

/// Small state shared with the WidgetKit extension through /Users/Shared.
/// Both targets declare the same sandbox temporary exception, so no App Group
/// (and no paid Developer team) is required.
struct SharedPlaybackState: Codable, Equatable, Sendable {
    var stationID: String
    var stationName: String
    var track: String?
    var isPlaying: Bool
    var updatedAt: Date

    static let directoryURL = URL(
        fileURLWithPath: "/Users/Shared/RadioMac",
        isDirectory: true
    )
    static let fileURL = directoryURL.appendingPathComponent("nowplaying.json")

    static func load() -> SharedPlaybackState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SharedPlaybackState.self, from: data)
    }

    func save() {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: Self.directoryURL,
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
