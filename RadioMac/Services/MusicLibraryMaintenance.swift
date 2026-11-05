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

    /// Collapses tracks that point at the same file. Re-imports across app
    /// container changes used to create copies with different absolute paths;
    /// rebasing can fold them onto one path later.
    func deduplicateTracks() {
        let groups = Dictionary(grouping: tracks.indices, by: { tracks[$0].path })
        guard groups.contains(where: { $0.value.count > 1 }) else { return }

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

        guard !removedToKept.isEmpty else { return }
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

        schedulePersist()
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
