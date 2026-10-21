import Foundation

/// The user's station library: built-in catalog plus their own streams.
@MainActor
final class StationLibrary: ObservableObject {
    private let defaults: UserDefaults

    @Published private(set) var stations: [RadioStation] = []

    private var resolving: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Derived

    var favorites: [RadioStation] { stations.filter(\.isFavorite) }

    /// User-defined groups, alphabetically. Stations without a group are not listed.
    var groups: [String] {
        let names = Set(stations.compactMap(\.group))
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

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
        group: String? = nil,
        logoURL: String? = nil,
        externalID: String? = nil
    ) -> RadioStation {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExternalID = Self.emptyToNil(externalID)
        if let existing = stations.first(where: {
            Self.sameStream($0, url: trimmedURL, externalID: trimmedExternalID)
        }) {
            return existing
        }

        let station = RadioStation(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: trimmedURL,
            genre: GenreCatalog.normalize(genre),
            comment: Self.emptyToNil(comment),
            group: normalizeGroup(group),
            logoURL: Self.emptyToNil(logoURL),
            externalID: trimmedExternalID
        )
        stations.append(station)
        persist()
        if !station.hasLogo {
            resolveLogo(for: station)
        }
        return station
    }

    func isDuplicate(url: String, externalID: String? = nil) -> Bool {
        stations.contains {
            Self.sameStream($0, url: url, externalID: Self.emptyToNil(externalID))
        }
    }

    private static func sameStream(
        _ station: RadioStation,
        url: String,
        externalID: String?
    ) -> Bool {
        if let externalID,
           let stored = station.externalID,
           stored.caseInsensitiveCompare(externalID) == .orderedSame {
            return true
        }
        return normalizedURL(station.url) == normalizedURL(url)
    }

    static func normalizedURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return components.url?.absoluteString ?? trimmed.lowercased()
    }

    func update(_ updated: RadioStation) {
        guard let index = stations.firstIndex(where: { $0.id == updated.id }) else { return }
        var next = updated
        next.genre = GenreCatalog.normalize(updated.genre)
        next.comment = Self.emptyToNil(updated.comment)
        next.group = normalizeGroup(updated.group)
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

    /// Moves a station before another one, preserving the library order.
    /// Trims a group and reuses the existing spelling when only the case differs.
    private func normalizeGroup(_ value: String?) -> String? {
        guard let trimmed = Self.emptyToNil(value) else { return nil }
        if let existing = stations.compactMap(\.group).first(where: {
            $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return existing
        }
        return trimmed
    }

    func move(id: String, before targetID: String) {
        guard id != targetID,
              let from = stations.firstIndex(where: { $0.id == id }),
              let target = stations.firstIndex(where: { $0.id == targetID })
        else { return }

        let station = stations.remove(at: from)
        let insertion = from < target ? target - 1 : target
        stations.insert(station, at: insertion)
        persist()
    }

    /// Moves a station to the end of the library.
    func moveToEnd(id: String) {
        guard let from = stations.firstIndex(where: { $0.id == id }),
              from != stations.count - 1
        else { return }
        let station = stations.remove(at: from)
        stations.append(station)
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
