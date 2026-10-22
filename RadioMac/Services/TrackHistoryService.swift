import Combine
import Foundation

/// Local-only history of the last 100 tracks.
@MainActor
final class TrackHistoryService: ObservableObject {
    @Published private(set) var entries: [TrackHistoryEntry] = []

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(
        player: RadioPlayerService? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        load()
        guard let player else { return }

        player.$nowPlaying
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                self?.record(track, station: player.station)
            }
            .store(in: &cancellables)
    }

    func record(_ track: NowPlaying, station: RadioStation?, at date: Date = Date()) {
        guard let station else { return }
        let title = track.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let artist = track.displayArtist
        if let last = entries.first,
           last.stationID == station.id,
           last.title == title,
           last.artist == artist {
            return
        }

        entries.insert(
            TrackHistoryEntry(
                station: station,
                title: title,
                artist: artist,
                playedAt: date
            ),
            at: 0
        )
        if entries.count > 100 {
            entries.removeLast(entries.count - 100)
        }
        persist()
    }

    func filtered(_ query: String) -> [TrackHistoryEntry] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return entries }
        return entries.filter { $0.searchText.contains(value) }
    }

    func clear() {
        entries = []
        defaults.removeObject(forKey: DefaultsKey.trackHistory)
    }

    func copyText(_ items: [TrackHistoryEntry]) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return items.map { entry in
            "\(formatter.string(from: entry.playedAt)) · \(entry.stationName) · \(entry.line)"
        }.joined(separator: "\n")
    }

    private func load() {
        guard let raw = defaults.string(forKey: DefaultsKey.trackHistory),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TrackHistoryEntry].self, from: data)
        else { return }
        entries = Array(decoded.prefix(100))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(raw, forKey: DefaultsKey.trackHistory)
    }
}
