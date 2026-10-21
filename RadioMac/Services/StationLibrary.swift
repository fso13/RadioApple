import Foundation

/// The user's station library: built-in catalog plus their own streams.
final class StationLibrary: ObservableObject {
    private let defaults: UserDefaults

    @Published private(set) var stations: [RadioStation] = []

    private var resolving: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Derived

    var favorites: [RadioStation] { stations.filter(\.isFavorite) }

    /// Genres in catalog order first, then custom genres alphabetically.
    var genres: [String] {
        var names = Set<String>()
        for station in stations {
            names.insert(GenreCatalog.normalize(station.genre))
        }
        let ordered = GenreCatalog.presets.filter(names.contains)
        let custom = names
            .filter { !GenreCatalog.presets.contains($0) }
            .sorted { $0.lowercased() < $1.lowercased() }
        return ordered + custom
    }

    func byID(_ id: String) -> RadioStation? {
        stations.first { $0.id == id }
    }

    // MARK: - Loading

    func load() {
        var loaded: [RadioStation] = []
        if let raw = defaults.stationsJSONString(),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([RadioStation].self, from: data) {
            loaded = decoded.filter { !$0.id.isEmpty && !$0.url.isEmpty }
        }

        if loaded.isEmpty {
            stations = DefaultStations.catalog
            persist()
        } else {
            stations = mergeMissingBuiltIns(into: loaded)
            stations = refreshBuiltInLogos(stations)
            persist()
        }

        resolveMissingLogos()
    }

    /// Adds newly shipped built-in stations without wiping user edits.
    private func mergeMissingBuiltIns(into existing: [RadioStation]) -> [RadioStation] {
        var merged = existing
        let existingIDs = Set(existing.map(\.id))
        let missing = DefaultStations.catalog.filter { !existingIDs.contains($0.id) }
        merged.append(contentsOf: missing)
        return merged
    }

    private func refreshBuiltInLogos(_ input: [RadioStation]) -> [RadioStation] {
        var catalog: [String: RadioStation] = [:]
        for station in DefaultStations.catalog { catalog[station.id] = station }

        return input.map { current in
            guard let shipped = catalog[current.id], shipped.hasLogo, !current.hasLogo else {
                return current
            }
            var updated = current
            updated.logoURL = shipped.logoURL
            return updated
        }
    }

    // MARK: - Mutations

    @discardableResult
    func add(
        name: String,
        url: String,
        genre: String,
        comment: String? = nil,
        logoURL: String? = nil
    ) -> RadioStation {
        let station = RadioStation(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            genre: GenreCatalog.normalize(genre),
            comment: Self.emptyToNil(comment),
            logoURL: Self.emptyToNil(logoURL)
        )
        stations.append(station)
        persist()
        if !station.hasLogo {
            resolveLogo(for: station)
        }
        return station
    }

    func update(_ updated: RadioStation) {
        guard let index = stations.firstIndex(where: { $0.id == updated.id }) else { return }
        var next = updated
        next.genre = GenreCatalog.normalize(updated.genre)
        next.comment = Self.emptyToNil(updated.comment)
        next.logoURL = Self.emptyToNil(updated.logoURL)
        stations[index] = next
        persist()
        if !next.hasLogo {
            resolveLogo(for: next)
        }
    }

    func remove(id: String) {
        stations.removeAll { $0.id == id }
        persist()
    }

    func toggleFavorite(id: String) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { return }
        stations[index].isFavorite.toggle()
        persist()
    }

    /// Re-seeds built-in stations; custom stations and favourites are preserved.
    func restoreDefaults() {
        let favoriteIDs = Set(stations.filter(\.isFavorite).map(\.id))
        let custom = stations.filter { !$0.builtIn }
        let restored = DefaultStations.catalog.map { station -> RadioStation in
            var copy = station
            copy.isFavorite = favoriteIDs.contains(station.id)
            return copy
        }
        stations = restored + custom
        persist()
    }

    // MARK: - Logo resolution

    func resolveMissingLogos() {
        let missing = stations.filter { !$0.hasLogo }
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            for station in missing {
                guard let logo = await LogoResolver.shared.resolve(
                    streamURL: station.url,
                    homepage: nil,
                    name: station.name
                ) else { continue }
                await MainActor.run {
                    self.applyResolvedLogo(id: station.id, logoURL: logo)
                }
            }
        }
    }

    func resolveFromHomepage(id: String, homepage: String) {
        guard let station = byID(id), !station.hasLogo else { return }
        Task { [weak self] in
            guard let logo = await LogoResolver.shared.resolve(
                streamURL: station.url,
                homepage: homepage,
                name: station.name
            ) else { return }
            guard let self else { return }
            await MainActor.run {
                self.applyResolvedLogo(id: id, logoURL: logo)
            }
        }
    }

    func applyResolvedLogo(id: String, logoURL: String) {
        guard let index = stations.firstIndex(where: { $0.id == id }),
              !stations[index].hasLogo
        else { return }
        stations[index].logoURL = logoURL
        persist()
    }

    private func resolveLogo(for station: RadioStation) {
        guard !station.hasLogo, !resolving.contains(station.id) else { return }
        resolving.insert(station.id)
        Task { [weak self] in
            let logo = await LogoResolver.shared.resolve(
                streamURL: station.url,
                homepage: nil,
                name: station.name
            )
            guard let self else { return }
            await MainActor.run {
                self.resolving.remove(station.id)
                if let logo {
                    self.applyResolvedLogo(id: station.id, logoURL: logo)
                }
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(stations),
              let json = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(json, forKey: DefaultsKey.stations)
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
