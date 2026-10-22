import Foundation

struct TrackHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let stationID: String
    let stationName: String
    let title: String
    let artist: String?
    let playedAt: Date

    init(
        id: String = UUID().uuidString,
        station: RadioStation,
        title: String,
        artist: String?,
        playedAt: Date = Date()
    ) {
        self.id = id
        stationID = station.id
        stationName = station.name
        self.title = title
        self.artist = artist
        self.playedAt = playedAt
    }

    var line: String {
        let prefix = artist.map { "\($0) — " } ?? ""
        return "\(prefix)\(title)"
    }

    var searchText: String {
        "\(stationName) \(line)".lowercased()
    }
}
