import Foundation

#if os(iOS)
/// App data containers get a new UUID on every development install. Library
/// paths are absolute, so they are rebased onto the current container at load.
private enum AppContainerPaths {
    private static let marker = "/Containers/Data/Application/"

    static func rebase(_ path: String) -> String {
        guard let range = path.range(of: marker) else { return path }
        let tail = path[range.upperBound...]
        guard let slash = tail.firstIndex(of: "/") else { return path }
        let relative = tail[tail.index(after: slash)...]
        return NSHomeDirectory() + "/" + relative
    }

    static func rebaseURL(_ value: String) -> String {
        guard value.hasPrefix("file://"), let url = URL(string: value) else { return value }
        let rebased = rebase(url.path)
        guard rebased != url.path else { return value }
        return URL(fileURLWithPath: rebased).absoluteString
    }
}
#endif

extension MusicLibrary {
    func hasAccess(toFolder url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return sources.contains { source in
            source.isFolder
                && (path == source.path || path.hasPrefix(source.path + "/"))
        }
    }

    /// Collapses tracks that point at the same file, then tracks that describe
    /// the same song (title, artist and duration). Re-imports and duplicated
    /// folders used to inflate the library even though the audio files were
    /// identical.
    func deduplicateTracks() {
        let byPath = collapseDuplicates { track in
            track.path.isEmpty ? nil : "path:\(track.path)"
        }
        let byMetadata = collapseDuplicates { track in
            Self.metadataKey(for: track)
        }
        if byPath || byMetadata { schedulePersist() }
    }

    /// Removes duplicates for one key, keeping the best-described track and
    /// remapping playlist references. Returns whether anything was removed.
    private func collapseDuplicates(key: (LocalTrack) -> String?) -> Bool {
        var groups: [String: [Int]] = [:]
        for index in tracks.indices {
            guard let value = key(tracks[index]) else { continue }
            groups[value, default: []].append(index)
        }

        var removedToKept: [String: String] = [:]
        for (_, indices) in groups where indices.count > 1 {
            let kept = indices.max { lhs, rhs in
                let left = Self.metadataScore(tracks[lhs])
                let right = Self.metadataScore(tracks[rhs])
                if left != right { return left < right }
                return tracks[lhs].addedAt > tracks[rhs].addedAt
            } ?? indices[0]

            for index in indices where index != kept {
                removedToKept[tracks[index].id] = tracks[kept].id
            }
        }

        guard !removedToKept.isEmpty else { return false }
        let removedIDs = Set(removedToKept.keys)

        tracks.removeAll { removedIDs.contains($0.id) }
        for id in removedIDs {
            MusicArtworkStore.remove(for: id)
        }

        for index in playlists.indices {
            var seen: Set<String> = []
            playlists[index].trackIDs = playlists[index].trackIDs.compactMap { id in
                let mapped = removedToKept[id] ?? id
                return seen.insert(mapped).inserted ? mapped : nil
            }
            playlists[index].updatedAt = Date()
        }

        return true
    }

    private static func metadataKey(for track: LocalTrack) -> String? {
        guard let title = LocalTrack.trimmed(track.displayTitle),
              let artist = LocalTrack.trimmed(track.displayArtist),
              let duration = track.duration,
              duration > 0
        else { return nil }

        let folded = { (value: String) in
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        }
        return "song:\(folded(title))|\(folded(artist))|\(Int(duration.rounded()))"
    }

    private static func metadataScore(_ track: LocalTrack) -> Int {
        var score = 0
        if track.hasArtwork { score += 8 }
        if track.displayAlbum != nil { score += 2 }
        if track.displayArtist != nil { score += 2 }
        if track.displayGenre != nil { score += 1 }
        if track.year != nil { score += 1 }
        if track.enrichedAt != nil { score += 1 }
        if !track.title.isEmpty { score += 1 }
        return score
    }

    #if os(iOS)
    func migrateContainerPaths() {
        var changed = false

        for index in tracks.indices {
            let path = AppContainerPaths.rebase(tracks[index].path)
            if path != tracks[index].path {
                tracks[index].path = path
                changed = true
            }
            if let artwork = tracks[index].artworkURL {
                let rebased = AppContainerPaths.rebaseURL(artwork)
                if rebased != artwork {
                    tracks[index].artworkURL = rebased
                    changed = true
                }
            }
        }

        for index in sources.indices {
            let path = AppContainerPaths.rebase(sources[index].path)
            if path != sources[index].path {
                sources[index].path = path
                changed = true
            }
        }

        for (name, artwork) in artistArtwork {
            let rebased = AppContainerPaths.rebaseURL(artwork)
            if rebased != artwork {
                artistArtwork[name] = rebased
                changed = true
            }
        }

        if changed { schedulePersist() }
    }

    /// Old media-library exports were named `UUID-Artist - Title.m4a`.
    /// When such a file was re-imported from the shared folder, the filename
    /// fallback turned the UUID prefix into part of the artist. Strip it once.
    func repairLegacyImportMetadata() {
        var changed = false

        for index in tracks.indices {
            let artist = Self.strippingUUIDPrefix(tracks[index].artist)
            if artist != tracks[index].artist {
                tracks[index].artist = artist
                changed = true
            }
            let title = Self.strippingUUIDPrefix(tracks[index].title) ?? tracks[index].title
            if title != tracks[index].title {
                tracks[index].title = title
                changed = true
            }
            let album = Self.strippingUUIDPrefix(tracks[index].album)
            if album != tracks[index].album {
                tracks[index].album = album
                changed = true
            }
        }

        if changed { schedulePersist() }
    }

    private static func strippingUUIDPrefix(_ value: String?) -> String? {
        guard let value else { return nil }
        let characters = Array(value)
        guard characters.count > 37 else { return value }

        let prefix = Array(characters.prefix(36))
        let groups = String(prefix).split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12],
              groups.joined().allSatisfy({ $0.isHexDigit }),
              characters[36] == "-"
        else { return value }

        return LocalTrack.trimmed(String(characters.dropFirst(37)))
    }

    /// Imports audio and M3U playlists the user dropped into the app's shared
    /// `Documents/Music` folder (Files app or Finder file sharing).
    func importSharedFolder() async -> (summary: MusicImportSummary, playlists: [String]) {
        let root = MusicImportCopier.directory
        let manager = FileManager.default
        let playlistExtensions = Set(MusicPlaylistFile.fileExtensions)
        let direct = (try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []

        var playlistMessages: [String] = []
        for url in direct where playlistExtensions.contains(url.pathExtension.lowercased()) {
            do {
                let imported = try await importPlaylist(from: url)
                playlistMessages.append("«\(imported.name)»: \(imported.addedTracks) треков")
            } catch {
                playlistMessages.append("Плейлист \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        let urls = collectAudioFiles(in: [root])
        if urls.isEmpty {
            var summary = MusicImportSummary()
            if playlistMessages.isEmpty {
                summary.errors = ["В папке RadioMac/Music нет аудиофайлов."]
            }
            return (summary, playlistMessages)
        }
        return (await addFiles(urls), playlistMessages)
    }
    #endif
}
