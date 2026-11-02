import Foundation

/// Albums, artists and covers derived from the local library.
extension MusicLibrary {
    // MARK: - Derived

    /// Albums of the whole library, ready for the cover grid.
    var albums: [MusicAlbum] {
        Self.albums(from: tracks)
    }

    /// Artists of the whole library, with their albums and covers.
    var artists: [MusicArtist] {
        Self.artists(from: tracks, artwork: artistArtwork)
    }

    func album(id: String) -> MusicAlbum? {
        albums.first { $0.id == id }
    }

    func artist(id: String) -> MusicArtist? {
        artists.first { $0.id == id }
    }

    // MARK: - Albums and artists

    /// Builds album cards from tracks using the same grouping keys as the
    /// table, so an album card and the "По альбому" section always agree.
    static func albums(from tracks: [LocalTrack]) -> [MusicAlbum] {
        sections(from: tracks, grouping: .album).map { section in
            let unnamed = section.tracks.allSatisfy { $0.displayAlbum == nil }
            return MusicAlbum(
                id: section.id,
                title: section.title,
                artist: unnamed
                    ? nil
                    : section.tracks.lazy.compactMap(\.displayArtist).first,
                year: section.tracks.lazy.compactMap(\.year).first,
                tracks: section.tracks,
                isUnnamed: unnamed
            )
        }
    }

    /// Builds artist cards, nesting the artist's albums and resolving the
    /// manually picked cover first, then any album cover.
    static func artists(
        from tracks: [LocalTrack],
        artwork: [String: String] = [:]
    ) -> [MusicArtist] {
        sections(from: tracks, grouping: .artist).map { section in
            let albums = albums(from: section.tracks)
            let unnamed = section.tracks.allSatisfy { $0.displayArtist == nil }
            let override = unnamed ? nil : artwork[section.title]
            return MusicArtist(
                id: section.id,
                name: section.title,
                albums: albums,
                tracks: section.tracks,
                artworkURL: override ?? albums.lazy.compactMap(\.artworkURL).first,
                isUnnamed: unnamed
            )
        }
    }

    // MARK: - Artwork

    /// Applies a cover to every track of the album, so the table, the player
    /// and the album card share one image. `nil` removes the artwork.
    func setArtwork(_ url: String?, for album: MusicAlbum) {
        guard !album.isUnnamed,
              let current = albums.first(where: { $0.id == album.id })
        else { return }
        let clean = LocalTrack.trimmed(url)
        let ids = Set(current.tracks.map(\.id))
        var changed = false
        for index in tracks.indices where ids.contains(tracks[index].id) {
            guard tracks[index].artworkURL != clean else { continue }
            tracks[index].artworkURL = clean
            changed = true
        }
        guard changed else { return }
        schedulePersist()
    }

    /// Stores an artist cover separately: applying one image to every track of
    /// an artist would erase the album covers.
    func setArtwork(_ url: String?, for artist: MusicArtist) {
        guard !artist.isUnnamed else { return }
        let clean = LocalTrack.trimmed(url)
        guard artistArtwork[artist.name] != clean else { return }
        if let clean {
            artistArtwork[artist.name] = clean
        } else {
            artistArtwork.removeValue(forKey: artist.name)
        }
        schedulePersist()
    }

    /// Album cover candidates: iTunes album search first, track search as a
    /// fallback for releases the album index does not know.
    func artworkCandidates(for album: MusicAlbum) async -> [TrackEnrichment] {
        guard !album.isUnnamed else { return [] }
        let direct = await enrichment.albumArtworkCandidates(
            title: album.title,
            artist: album.artist
        )
        if !direct.isEmpty { return direct }
        guard let first = album.tracks.first else { return [] }
        return await enrichment.candidates(
            title: first.displayTitle,
            artist: album.artist ?? first.displayArtist,
            album: album.title
        )
    }

    /// Artist cover candidates: Deezer artist portraits first, album covers of
    /// the artist as a fallback.
    func artworkCandidates(for artist: MusicArtist) async -> [TrackEnrichment] {
        guard !artist.isUnnamed else { return [] }
        let direct = await enrichment.artistArtworkCandidates(name: artist.name)
        if !direct.isEmpty { return direct }
        for album in artist.albums.prefix(2) {
            let candidates = await artworkCandidates(for: album)
            if !candidates.isEmpty { return candidates }
        }
        return []
    }
}
