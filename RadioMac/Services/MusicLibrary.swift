#if os(macOS)
import AppKit
#endif
import Combine
import Foundation


enum MusicLibraryError: LocalizedError {
    case unreadable(String)
    case emptyPlaylist
    case unsupportedFile(String)
    case noAccess(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "Не удалось прочитать «\(name)»."
        case .emptyPlaylist:
            return "В плейлисте нет локальных файлов."
        case .unsupportedFile(let name):
            return "«\(name)» — не аудиофайл."
        case .noAccess(let name):
            return "Нет доступа к «\(name)». Добавьте папку в источниках музыки."
        }
    }
}

/// The user's local music: audio files from granted folders, playlists and
/// online-enriched metadata. Everything is stored in the app container; audio
/// files are never modified.
@MainActor
final class MusicLibrary: ObservableObject {
    @Published var tracks: [LocalTrack] = []
    @Published var playlists: [MusicPlaylist] = []
    @Published var sources: [MusicSource] = []
    /// Manually picked artist covers, keyed by the displayed artist name.
    @Published var artistArtwork: [String: String] = [:]

    @Published private(set) var isScanning = false
    @Published private(set) var scanStatus: String?
    @Published private(set) var isEnriching = false
    @Published private(set) var enrichmentStatus: String?

    /// Pull covers and album names for new tracks automatically.
    @Published private(set) var autoEnrich: Bool

    private let storageURL: URL?
    private let defaults: UserDefaults
    let enrichment = MetadataEnrichmentService.shared

    private var activeScopes: [String: URL] = [:]
    private var startedScopes: Set<String> = []
    private var saveTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    /// Debug harness snapshots seed an in-memory library; nothing is written.
    private var persistenceEnabled = true

    init(
        storageURL: URL? = MusicLibrary.defaultStorageURL,
        defaults: UserDefaults = .standard
    ) {
        self.storageURL = storageURL
        self.defaults = defaults
        autoEnrich = defaults.boolLike(DefaultsKey.musicAutoEnrich) ?? true
    }

    // MARK: - Derived

    var isEmpty: Bool { tracks.isEmpty }

    var missingCount: Int {
        tracks.filter(\.isMissing).count
    }

    func tracks(in playlistID: String?) -> [LocalTrack] {
        guard let playlistID else { return tracks }
        guard let playlist = playlist(id: playlistID) else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { byID[$0] }
    }

    func filteredTracks(
        query: String,
        playlistID: String?,
        sort: MusicSortOrder
    ) -> [LocalTrack] {
        var items = tracks(in: playlistID)
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !needle.isEmpty {
            items = items.filter { $0.searchText.contains(needle) }
        }
        return sorted(items, by: sort)
    }

    func sorted(_ items: [LocalTrack], by order: MusicSortOrder) -> [LocalTrack] {
        switch order {
        case .manual:
            return items
        case .added:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return items.sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        case .artist:
            return items.sorted {
                let left = $0.displayArtist ?? "\u{FFFF}"
                let right = $1.displayArtist ?? "\u{FFFF}"
                if left == right {
                    return $0.displayTitle.localizedStandardCompare($1.displayTitle)
                        == .orderedAscending
                }
                return left.localizedStandardCompare(right) == .orderedAscending
            }
        case .album:
            return items.sorted {
                let left = $0.displayAlbum ?? "\u{FFFF}"
                let right = $1.displayAlbum ?? "\u{FFFF}"
                if left == right {
                    let leftNumber = $0.trackNumber ?? 0
                    let rightNumber = $1.trackNumber ?? 0
                    if leftNumber != rightNumber { return leftNumber < rightNumber }
                    return $0.displayTitle.localizedStandardCompare($1.displayTitle)
                        == .orderedAscending
                }
                return left.localizedStandardCompare(right) == .orderedAscending
            }
        case .duration:
            return items.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
    }

    /// Rows of the music table, split into sections when a grouping is picked.
    func sections(
        query: String,
        playlistID: String?,
        sort: MusicSortOrder,
        grouping: MusicGrouping
    ) -> [MusicTrackSection] {
        Self.sections(
            from: filteredTracks(query: query, playlistID: playlistID, sort: sort),
            grouping: grouping
        )
    }

    /// Splits already filtered tracks into groups. Groups are ordered by name
    /// with the unnamed one last; tracks inside a group follow album and
    /// track-number order, so an album never mixes its songs up.
    static func sections(from items: [LocalTrack], grouping: MusicGrouping) -> [MusicTrackSection] {
        guard grouping != .none else {
            return [MusicTrackSection(id: "all", title: "", subtitle: nil, tracks: items)]
        }

        var buckets: [String: GroupBucket] = [:]
        for item in items {
            let key = groupKey(for: item, grouping: grouping)
            if var bucket = buckets[key] {
                bucket.tracks.append(item)
                buckets[key] = bucket
            } else {
                buckets[key] = GroupBucket(
                    title: groupTitle(for: item, grouping: grouping),
                    subtitle: groupSubtitle(for: item, grouping: grouping),
                    isUnnamed: isUnnamed(item, grouping: grouping),
                    tracks: [item]
                )
            }
        }

        return buckets
            .map { key, bucket in
                (
                    bucket,
                    MusicTrackSection(
                        id: "\(grouping.rawValue):\(key)",
                        title: bucket.title,
                        subtitle: bucket.subtitle,
                        tracks: bucket.tracks.sorted { comesBefore($0, $1, grouping: grouping) }
                    )
                )
            }
            .sorted { left, right in
                if left.0.isUnnamed != right.0.isUnnamed { return !left.0.isUnnamed }
                let order = left.1.title.localizedStandardCompare(right.1.title)
                if order != .orderedSame { return order == .orderedAscending }
                let leftSubtitle = left.1.subtitle ?? ""
                let rightSubtitle = right.1.subtitle ?? ""
                let subtitleOrder = leftSubtitle.localizedStandardCompare(rightSubtitle)
                if subtitleOrder != .orderedSame { return subtitleOrder == .orderedAscending }
                return left.1.id < right.1.id
            }
            .map { $0.1 }
    }

    // MARK: - Grouping internals

    private struct GroupBucket {
        var title: String
        var subtitle: String?
        var isUnnamed: Bool
        var tracks: [LocalTrack]
    }

    /// Sorts after every real name, so "Без исполнителя" is always last.
    private static let unknownGroupKey = "\u{FFFF}"

    private static func groupKey(for track: LocalTrack, grouping: MusicGrouping) -> String {
        switch grouping {
        case .none:
            return ""
        case .artist:
            return track.displayArtist ?? unknownGroupKey
        case .album:
            guard let album = track.displayAlbum else { return unknownGroupKey }
            // The same album title by different artists is a different album.
            return album + "\u{1F}" + (track.displayArtist ?? "")
        case .genre:
            return track.displayGenre ?? unknownGroupKey
        }
    }

    private static func groupTitle(for track: LocalTrack, grouping: MusicGrouping) -> String {
        switch grouping {
        case .none: return ""
        case .artist: return track.displayArtist ?? "Без исполнителя"
        case .album: return track.displayAlbum ?? "Без альбома"
        case .genre: return track.displayGenre ?? "Без жанра"
        }
    }

    private static func groupSubtitle(for track: LocalTrack, grouping: MusicGrouping) -> String? {
        guard grouping == .album, track.displayAlbum != nil else { return nil }
        let parts = [track.displayArtist, track.year.map(String.init)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func isUnnamed(_ track: LocalTrack, grouping: MusicGrouping) -> Bool {
        switch grouping {
        case .none: return false
        case .artist: return track.displayArtist == nil
        case .album: return track.displayAlbum == nil
        case .genre: return track.displayGenre == nil
        }
    }

    private static func comesBefore(
        _ lhs: LocalTrack,
        _ rhs: LocalTrack,
        grouping: MusicGrouping
    ) -> Bool {
        var comparisons: [Bool?]
        switch grouping {
        case .none:
            comparisons = []
        case .artist:
            comparisons = [
                lessOptional(lhs.displayAlbum, rhs.displayAlbum),
                lessOptional(lhs.trackNumber, rhs.trackNumber),
            ]
        case .album:
            comparisons = [lessOptional(lhs.trackNumber, rhs.trackNumber)]
        case .genre:
            comparisons = [
                lessOptional(lhs.displayArtist, rhs.displayArtist),
                lessOptional(lhs.displayAlbum, rhs.displayAlbum),
                lessOptional(lhs.trackNumber, rhs.trackNumber),
            ]
        }
        for comparison in comparisons {
            if let comparison { return comparison }
        }
        return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }

    /// `nil` sorts last; equal values fall through to the next comparison.
    private static func lessOptional(_ lhs: String?, _ rhs: String?) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?):
            guard left != right else { return nil }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private static func lessOptional(_ lhs: Int?, _ rhs: Int?) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil): return nil
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?):
            guard left != right else { return nil }
            return left < right
        }
    }

    // MARK: - Loading

    func load() {
        #if os(iOS)
        migrateLibraryFileIfNeeded(at: storageURL)
        #endif
        guard let readURL = Self.readURL(for: storageURL),
              let data = try? Data(contentsOf: readURL)
        else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return
        }
        tracks = snapshot.tracks.filter { !$0.path.isEmpty }
        playlists = snapshot.playlists
        sources = snapshot.sources
        artistArtwork = snapshot.artistArtwork ?? [:]
        #if os(iOS)
        migrateContainerPaths()
        #endif
        deduplicateTracks()
        #if os(iOS)
        migrateArtworkFiles()
        repairLegacyImportMetadata()
        #endif

        for source in sources {
            _ = startAccess(for: source)
        }
        refreshMissingFlags()
    }


    /// Writes pending changes immediately. Called when the app quits.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persistNow()
    }

    func setAutoEnrich(_ value: Bool) {
        guard value != autoEnrich else { return }
        autoEnrich = value
        defaults.set(value, forKey: DefaultsKey.musicAutoEnrich)
    }

    // MARK: - Sources

    @discardableResult
    func addFolder(_ url: URL) async -> MusicImportSummary {
        #if os(iOS)
        guard let local = await MusicImportCopier.copy(url) else {
            var failure = MusicImportSummary()
            failure.missing = 1
            return failure
        }
        let summary = await addFolderWithoutEnrichment(local)
        #else
        let summary = await addFolderWithoutEnrichment(url)
        #endif
        startEnrichmentIfNeeded()
        return summary
    }

    @discardableResult
    func addFiles(_ urls: [URL]) async -> MusicImportSummary {
        var summary = MusicImportSummary()
        var audioURLs: [URL] = []
        #if os(iOS)
        var candidates: [URL] = []
        for url in urls {
            if let local = await MusicImportCopier.copy(url) {
                candidates.append(local)
            } else {
                summary.missing += 1
            }
        }
        #else
        let candidates = urls
        #endif
        for url in candidates {
            let standardized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
                summary.missing += 1
                continue
            }
            if isDirectory.boolValue {
                let folder = await addFolderWithoutEnrichment(standardized)
                summary.added += folder.added
                summary.skipped += folder.skipped
                summary.missing += folder.missing
                summary.errors.append(contentsOf: folder.errors)
            } else if MusicPlaylistFile.fileExtensions.contains(standardized.pathExtension.lowercased()) {
                summary.errors.append("«\(standardized.lastPathComponent)» — плейлист, импортируйте его отдельно.")
            } else if LocalAudioMetadata.isSupported(standardized) {
                ensureSource(for: standardized)
                audioURLs.append(standardized)
            } else {
                summary.skipped += 1
                summary.errors.append("«\(standardized.lastPathComponent)» — не поддерживаемый формат.")
            }
        }

        if !audioURLs.isEmpty {
            let imported = await importAudioFiles(audioURLs)
            summary.added += imported.added
            summary.skipped += imported.skipped
            summary.missing += imported.missing
            summary.errors.append(contentsOf: imported.errors)
        }
        startEnrichmentIfNeeded()
        return summary
    }


    private func addFolderWithoutEnrichment(_ url: URL) async -> MusicImportSummary {
        let standardized = url.standardizedFileURL
        if let existing = sources.first(where: { $0.path == standardized.path }) {
            _ = startAccess(for: existing)
        } else {
            let source = makeSource(for: standardized, isFolder: true)
            sources.append(source)
            _ = startAccess(for: source)
            schedulePersist()
        }
        let urls = collectAudioFiles(in: [standardized])
        return await importAudioFiles(urls)
    }

    /// Grants access to a folder without scanning it yet (used by M3U import).
    @discardableResult
    func grantFolderAccess(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        if hasAccess(toFolder: standardized) { return true }
        let source = makeSource(for: standardized, isFolder: true)
        sources.append(source)
        let started = startAccess(for: source) != nil
        schedulePersist()
        return started
    }

    func rescan() {
        guard scanTask == nil, !isScanning else { return }
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRescan()
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanStatus = nil
    }

    private func runRescan() async {
        guard !sources.isEmpty else { return }
        isScanning = true
        scanStatus = "Сканирую папки…"
        defer {
            isScanning = false
            scanStatus = nil
        }

        var urls: [URL] = []
        for source in sources {
            guard let folder = startAccess(for: source) else { continue }
            urls.append(contentsOf: collectAudioFiles(in: [folder]))
        }
        let summary = await importAudioFiles(urls)
        refreshMissingFlags()
        if summary.added > 0 {
            deduplicateTracks()
            startEnrichmentIfNeeded()
        }
        flush()
    }

    func removeSource(id: String) {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        stopAccess(for: source.id)
        sources.removeAll { $0.id == id }

        let prefix = source.path + "/"
        let removedIDs = Set(
            tracks.filter { $0.path == source.path || $0.path.hasPrefix(prefix) }.map(\.id)
        )
        if !removedIDs.isEmpty {
            removeTracks(ids: removedIDs)
        }
        schedulePersist()
    }

    // MARK: - Tracks

    func update(_ track: LocalTrack) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        var updated = track
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.artist = LocalTrack.trimmed(updated.artist)
        updated.album = LocalTrack.trimmed(updated.album)
        updated.genre = LocalTrack.trimmed(updated.genre)
        updated.year = LocalTrack.validYear(updated.year)
        tracks[index] = updated
        schedulePersist()
    }

    func removeTrack(id: String) {
        removeTracks(ids: [id])
    }

    func removeTracks(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        tracks.removeAll { ids.contains($0.id) }
        for index in playlists.indices {
            let filtered = playlists[index].trackIDs.filter { !ids.contains($0) }
            if filtered.count != playlists[index].trackIDs.count {
                playlists[index].trackIDs = filtered
                playlists[index].updatedAt = Date()
            }
        }
        for id in ids { MusicArtworkStore.remove(for: id) }
        schedulePersist()
    }

    // MARK: - Ordering

    /// Stores the custom order of the whole library, used by `.manual` sorting.
    /// IDs that no longer exist are ignored; new tracks not listed keep their
    /// relative order at the end.
    func setTrackOrder(_ orderedIDs: [String]) {
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var reordered = orderedIDs.compactMap { byID[$0] }
        let seen = Set(reordered.map(\.id))
        reordered.append(contentsOf: tracks.filter { !seen.contains($0.id) })
        guard reordered.map(\.id) != tracks.map(\.id) else { return }
        tracks = reordered
        schedulePersist()
    }

    /// Stores the custom order inside one playlist.
    func setTrackOrder(_ orderedIDs: [String], in playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let playable = Set(tracks.map(\.id))
        let existing = Set(playlists[index].trackIDs)
        var reordered = orderedIDs.filter { playable.contains($0) && existing.contains($0) }
        let seen = Set(reordered)
        reordered.append(contentsOf: playlists[index].trackIDs.filter { !seen.contains($0) })
        guard reordered != playlists[index].trackIDs else { return }
        playlists[index].trackIDs = reordered
        playlists[index].updatedAt = Date()
        schedulePersist()
    }

    func revealInFinder(_ track: LocalTrack) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
        #endif
    }

    func refreshMissingFlags() {
        guard !tracks.isEmpty else { return }
        var changed = false
        for index in tracks.indices {
            let exists = FileManager.default.fileExists(atPath: tracks[index].path)
            if tracks[index].isMissing == exists {
                tracks[index].isMissing = !exists
                changed = true
            }
        }
        if changed { schedulePersist() }
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(
        name: String,
        trackIDs: [String] = [],
        sourceName: String? = nil,
        folderPath: String? = nil
    ) -> MusicPlaylist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let playlist = MusicPlaylist(
            name: uniquePlaylistName(for: trimmed),
            trackIDs: trackIDs.filter { id in tracks.contains { $0.id == id } },
            sourceName: sourceName,
            folderPath: folderPath
        )
        playlists.append(playlist)
        schedulePersist()
        return playlist
    }

    func renamePlaylist(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = playlists.firstIndex(where: { $0.id == id })
        else { return }
        let taken = playlists.contains {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        playlists[index].name = taken ? uniquePlaylistName(for: trimmed, ignoring: id) : trimmed
        playlists[index].updatedAt = Date()
        schedulePersist()
    }

    func deletePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
        schedulePersist()
    }

    func addTracks(_ trackIDs: [String], to playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let valid = trackIDs.filter { id in tracks.contains { $0.id == id } }
        let existing = Set(playlists[index].trackIDs)
        let additions = valid.filter { !existing.contains($0) }
        guard !additions.isEmpty else { return }
        playlists[index].trackIDs.append(contentsOf: additions)
        playlists[index].updatedAt = Date()
        schedulePersist()
    }

    func removeTrack(_ trackID: String, from playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs.removeAll { $0 == trackID }
        playlists[index].updatedAt = Date()
        schedulePersist()
    }

    // MARK: - M3U

    func m3uData(for playlistID: String) -> Data? {
        guard let playlist = playlist(id: playlistID) else { return nil }
        let items = tracks(in: playlistID)
        return MusicPlaylistFile.exportData(name: playlist.name, tracks: items)
    }

    @discardableResult
    func importPlaylist(from url: URL) async throws -> MusicPlaylistImportResult {
        let standardized = url.standardizedFileURL
        guard let data = try? Data(contentsOf: standardized) else {
            throw MusicLibraryError.unreadable(standardized.lastPathComponent)
        }
        let parsed = MusicPlaylistFile.parse(data)
        guard !parsed.isEmpty else { throw MusicLibraryError.emptyPlaylist }

        let folder = standardized.deletingLastPathComponent()
        if hasAccess(toFolder: folder) == false, sources.contains(where: { $0.path == folder.path }) == false {
            // Reading the playlist file works through the open panel grant; the
            // sibling folder needs its own permission, which the UI asks for.
            grantFolderAccess(folder)
        }

        var fileURLs: [URL] = []
        var skipped = 0
        for entry in parsed.entries {
            guard let fileURL = MusicPlaylistFile.resolvedURL(
                for: entry.location,
                relativeTo: standardized
            ) else {
                skipped += 1
                continue
            }
            guard LocalAudioMetadata.isSupported(fileURL),
                  FileManager.default.fileExists(atPath: fileURL.path)
            else {
                skipped += 1
                continue
            }
            fileURLs.append(fileURL.standardizedFileURL)
        }

        let summary = await importAudioFiles(fileURLs)
        let paths = fileURLs.map(\.path)
        let order = Dictionary(uniqueKeysWithValues: tracks.map { ($0.path, $0.id) })
        let orderedIDs = paths.compactMap { order[$0] }
        let name = parsed.name ?? standardized.deletingPathExtension().lastPathComponent
        let playlist = createPlaylist(
            name: name,
            trackIDs: orderedIDs,
            sourceName: standardized.lastPathComponent
        )
        guard let playlist else { throw MusicLibraryError.emptyPlaylist }

        startEnrichmentIfNeeded()
        return MusicPlaylistImportResult(
            playlistID: playlist.id,
            name: playlist.name,
            addedTracks: summary.added,
            skippedEntries: skipped + summary.skipped + summary.missing
        )
    }

    // MARK: - Enrichment

    func startEnrichment(limit: Int = 0) {
        guard enrichmentTask == nil, !isEnriching else { return }
        enrichmentTask = Task { @MainActor [weak self] in
            await self?.runEnrichment(limit: limit)
            self?.enrichmentTask = nil
        }
    }

    func cancelEnrichment() {
        enrichmentTask?.cancel()
    }

    @discardableResult
    func enrich(trackID: String) async -> TrackEnrichment? {
        guard let track = track(id: trackID), !track.isMissing else { return nil }
        let match = await enrichment.bestMatch(for: track)
        if let match {
            apply(match, to: trackID, overwrite: false)
        }
        return match
    }

    func apply(_ match: TrackEnrichment, to trackID: String, overwrite: Bool = false) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        var track = tracks[index]
        let changes = match.changes(for: track)

        if overwrite {
            if let value = LocalTrack.trimmed(match.title) { track.title = value }
            if let value = LocalTrack.trimmed(match.artist) { track.artist = value }
            if let value = LocalTrack.trimmed(match.album) { track.album = value }
            if let value = LocalTrack.trimmed(match.genre) { track.genre = value }
            if let value = match.year { track.year = value }
            if let value = LocalTrack.trimmed(match.artworkURL) { track.artworkURL = value }
        } else {
            if let value = changes.title { track.title = value }
            if let value = changes.artist { track.artist = value }
            if let value = changes.album { track.album = value }
            if let value = changes.genre { track.genre = value }
            if let value = changes.year { track.year = value }
            if let value = changes.artworkURL { track.artworkURL = value }
        }

        guard overwrite || !changes.isEmpty else { return }
        track.enrichedAt = Date()
        track.enrichmentSource = match.source
        tracks[index] = track
        schedulePersist()
    }

    private func startEnrichmentIfNeeded() {
        guard autoEnrich else { return }
        startEnrichment(limit: 500)
    }

    private func runEnrichment(limit: Int) async {
        isEnriching = true
        defer {
            isEnriching = false
            enrichmentStatus = nil
        }

        let targets = tracks.filter(\.needsEnrichment)
        guard !targets.isEmpty else { return }
        let capped = limit > 0 ? Array(targets.prefix(limit)) : targets

        var updated = 0
        var misses = 0
        for (offset, target) in capped.enumerated() {
            if Task.isCancelled { break }
            enrichmentStatus = "Обогащение \(offset + 1) из \(capped.count)…"
            guard let match = await enrichment.bestMatch(for: target) else {
                misses += 1
                // Three empty answers in a row usually mean there is no network;
                // do not spend minutes timing out on the rest of the library.
                if misses >= 3 {
                    enrichmentStatus = "Сеть недоступна — обогащение остановлено"
                    break
                }
                continue
            }
            misses = 0
            let before = track(id: target.id)
            apply(match, to: target.id, overwrite: false)
            if track(id: target.id) != before { updated += 1 }
            try? await Task.sleep(nanoseconds: 220_000_000)
        }
        flush()
    }

    // MARK: - Scanning internals

    private func ensureSource(for url: URL) {
        if let source = sources.first(where: { $0.isFolder && covers($0, url: url) }) {
            _ = startAccess(for: source)
            return
        }
        if let source = sources.first(where: { $0.path == url.path }) {
            _ = startAccess(for: source)
            return
        }
        let source = makeSource(for: url, isFolder: false)
        sources.append(source)
        _ = startAccess(for: source)
        schedulePersist()
    }

    private func covers(_ source: MusicSource, url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(source.path + "/")
    }

    private func makeSource(for url: URL, isFolder: Bool) -> MusicSource {
        MusicSource(
            path: url.standardizedFileURL.path,
            isFolder: isFolder,
            bookmark: Self.bookmarkData(for: url)
        )
    }

    func collectAudioFiles(in folders: [URL]) -> [URL] {
        var found: [URL] = []
        for folder in folders {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
                continue
            }
            if !isDirectory.boolValue {
                if LocalAudioMetadata.isSupported(folder) { found.append(folder.standardizedFileURL) }
                continue
            }
            let keys: [URLResourceKey] = [.isRegularFileKey]
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let fileURL as URL in enumerator
            where LocalAudioMetadata.isSupported(fileURL) {
                found.append(fileURL.standardizedFileURL)
            }
        }
        return found
    }

    private func importAudioFiles(_ urls: [URL]) async -> MusicImportSummary {
        var summary = MusicImportSummary()
        guard !urls.isEmpty else { return summary }

        let existingPaths = Set(tracks.map(\.path))
        var seen: Set<String> = []
        var newURLs: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            if existingPaths.contains(path) { continue }
            guard LocalAudioMetadata.isSupported(url) else {
                summary.skipped += 1
                continue
            }
            guard FileManager.default.fileExists(atPath: path) else {
                summary.missing += 1
                continue
            }
            newURLs.append(url.standardizedFileURL)
        }
        guard !newURLs.isEmpty else { return summary }
        newURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        isScanning = true
        defer {
            isScanning = false
            scanStatus = nil
        }

        var created: [LocalTrack] = []
        var skipped = 0
        let batchSize = 6
        var offset = 0
        while offset < newURLs.count {
            if Task.isCancelled { break }
            let batch = Array(newURLs[offset..<min(offset + batchSize, newURLs.count)])
            let pairs = await withTaskGroup(
                of: (URL, AudioFileMetadata).self,
                returning: [(URL, AudioFileMetadata)].self
            ) { group in
                for url in batch {
                    group.addTask { (url, await LocalAudioMetadata.read(at: url)) }
                }
                var collected: [(URL, AudioFileMetadata)] = []
                for await pair in group { collected.append(pair) }
                return collected
            }
            for (url, metadata) in pairs {
                guard metadata.playable else {
                    skipped += 1
                    continue
                }
                created.append(makeTrack(url: url, metadata: metadata))
            }
            offset += batchSize
            scanStatus = "Читаю теги: \(min(offset, newURLs.count)) из \(newURLs.count)"
            await Task.yield()
        }

        if !created.isEmpty {
            tracks.append(contentsOf: created)
            summary.added = created.count
        }
        summary.skipped += skipped
        schedulePersist()
        return summary
    }

    private func makeTrack(url: URL, metadata: AudioFileMetadata) -> LocalTrack {
        let fallback = LocalAudioMetadata.fallback(from: url)
        var track = LocalTrack(
            path: url.standardizedFileURL.path,
            title: metadata.title ?? fallback.title,
            artist: metadata.artist ?? fallback.artist,
            album: metadata.album,
            genre: metadata.genre,
            year: metadata.year,
            trackNumber: metadata.trackNumber,
            duration: metadata.duration
        )
        if let data = metadata.artworkData {
            track.artworkURL = MusicArtworkStore.save(data, for: track.id)
        }
        return track
    }

    // MARK: - Security-scoped access

    private func startAccess(for source: MusicSource) -> URL? {
        if let active = activeScopes[source.id] { return active }

        #if os(macOS)
        if let bookmark = source.bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if url.startAccessingSecurityScopedResource() {
                    startedScopes.insert(source.id)
                }
                activeScopes[source.id] = url
                if stale, let fresh = Self.bookmarkData(for: url),
                   let index = sources.firstIndex(where: { $0.id == source.id }) {
                    sources[index].bookmark = fresh
                    schedulePersist()
                }
                return url
            }
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                activeScopes[source.id] = url
                return url
            }
        }
        #endif

        let fallback = URL(fileURLWithPath: source.path)
        guard FileManager.default.fileExists(atPath: fallback.path) else { return nil }
        activeScopes[source.id] = fallback
        return fallback
    }

    private func stopAccess(for sourceID: String) {
        if startedScopes.contains(sourceID) {
            activeScopes[sourceID]?.stopAccessingSecurityScopedResource()
            startedScopes.remove(sourceID)
        }
        activeScopes.removeValue(forKey: sourceID)
    }

    static func bookmarkData(for url: URL) -> Data? {
        #if os(macOS)
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        // iOS has no security-scoped bookmarks for arbitrary folders; imported
        // audio is copied into the container instead (see `MusicImportCopier`).
        return nil
        #endif
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var tracks: [LocalTrack]
        var playlists: [MusicPlaylist]
        var sources: [MusicSource]
        var artistArtwork: [String: String]?
    }

    func schedulePersist() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistNow()
        }
    }

    private func persistNow() {
        guard persistenceEnabled, let storageURL else { return }
        let snapshot = Snapshot(
            tracks: tracks,
            playlists: playlists,
            sources: sources,
            artistArtwork: artistArtwork
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // A failed write must not break playback; the next change retries.
        }
    }

    private func uniquePlaylistName(for name: String, ignoring id: String? = nil) -> String {
        let taken = { (candidate: String) -> Bool in
            self.playlists.contains {
                $0.id != id && $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame
            }
        }
        guard taken(name) else { return name }
        var counter = 2
        while taken("\(name) \(counter)") { counter += 1 }
        return "\(name) \(counter)"
    }

#if DEBUG
    /// Snapshot-only helper: installs a library without touching the real one.
    func debugInstall(tracks: [LocalTrack], playlists: [MusicPlaylist] = []) {
        persistenceEnabled = false
        self.tracks = tracks
        self.playlists = playlists
    }
#endif

}

#if os(iOS)
/// Copies files and folders picked in the Files app into the app container.
///
/// iOS has no security-scoped bookmarks for arbitrary locations, so imported
/// audio is copied once and then read from the sandbox for the lifetime of the
/// library. The copy keeps the original file name and avoids overwriting an
/// earlier import.
enum MusicImportCopier {
    /// Where imported audio lives. The container is always readable by the app.
    static var directory: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("Music", isDirectory: true)
    }

    static func copy(_ url: URL) async -> URL? {
        let root = directory
        // Files that already live in the import folder (dropped there through
        // Files or Finder file sharing) are used in place, not copied again.
        if url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") {
            return url
        }
        return await Task.detached(priority: .userInitiated) { [url, root] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            let manager = FileManager.default
            guard manager.fileExists(atPath: url.path) else { return nil }
            do {
                try manager.createDirectory(at: root, withIntermediateDirectories: true)
                let destination = uniqueDestination(for: url.lastPathComponent, in: root)
                try manager.copyItem(at: url, to: destination)
                return destination
            } catch {
                return nil
            }
        }.value
    }

    private static func uniqueDestination(for name: String, in directory: URL) -> URL {
        let manager = FileManager.default
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        while manager.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            candidate = directory.appendingPathComponent("\(base) \(counter)\(suffix)")
            counter += 1
        }
        return candidate
    }
}
#endif
