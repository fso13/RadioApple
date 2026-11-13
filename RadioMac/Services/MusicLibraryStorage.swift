import Foundation

extension MusicLibrary {
    func track(id: String) -> LocalTrack? {
        tracks.first { $0.id == id }
    }

    func playlist(id: String) -> MusicPlaylist? {
        playlists.first { $0.id == id }
    }

    static var defaultStorageURL: URL? {
        #if os(iOS)
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #endif
        return base?
            .appendingPathComponent("RadioMac", isDirectory: true)
            .appendingPathComponent("music-library.json")
    }

    #if os(iOS)
    /// Pre-Documents library location, read once and copied on first launch.
    static var legacyStorageURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("RadioMac", isDirectory: true)
            .appendingPathComponent("music-library.json")
    }
    #endif

    /// Returns the readable library file: Documents first, then the legacy
    /// Application Support location used by older iOS builds.
    static func readURL(for storageURL: URL?) -> URL? {
        guard let storageURL else { return nil }
        let manager = FileManager.default
        if manager.fileExists(atPath: storageURL.path) { return storageURL }
        #if os(iOS)
        if let legacy = legacyStorageURL, manager.fileExists(atPath: legacy.path) {
            return legacy
        }
        #endif
        return storageURL
    }

    #if os(iOS)
    /// The library index lives in Documents so it survives development
    /// re-installs together with the audio files. Older builds kept it in
    /// Application Support; copy that file once.
    func migrateLibraryFileIfNeeded(at storageURL: URL?) {
        guard let storageURL else { return }
        let manager = FileManager.default
        guard !manager.fileExists(atPath: storageURL.path),
              let legacy = Self.legacyStorageURL,
              manager.fileExists(atPath: legacy.path)
        else { return }
        do {
            try manager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try manager.copyItem(at: legacy, to: storageURL)
        } catch {
            // Reading from the legacy location still works via `readURL`.
        }
    }

    /// Covers used to live in Application Support; move them next to the
    /// library index in Documents and update paths in the library.
    func migrateArtworkFiles() {
        guard let legacy = MusicArtworkStore.legacyDirectory else { return }
        let legacyPrefix = legacy.path + "/"
        let newDirectory = MusicArtworkStore.directory
        let manager = FileManager.default
        var changed = false

        func migrate(_ value: String?) -> String? {
            guard let value,
                  value.hasPrefix("file://"),
                  let url = URL(string: value),
                  url.path.hasPrefix(legacyPrefix),
                  manager.fileExists(atPath: url.path)
            else { return value }

            let destination = newDirectory.appendingPathComponent(url.lastPathComponent)
            if !manager.fileExists(atPath: destination.path) {
                try? manager.createDirectory(
                    at: newDirectory,
                    withIntermediateDirectories: true
                )
                try? manager.copyItem(at: url, to: destination)
            }
            guard manager.fileExists(atPath: destination.path) else { return value }
            return destination.absoluteString
        }

        for index in tracks.indices {
            let migrated = migrate(tracks[index].artworkURL)
            if migrated != tracks[index].artworkURL {
                tracks[index].artworkURL = migrated
                changed = true
            }
        }

        for (name, value) in artistArtwork {
            let migrated = migrate(value)
            if migrated != value {
                artistArtwork[name] = migrated
                changed = true
            }
        }

        if changed { schedulePersist() }
    }
    #endif
}
