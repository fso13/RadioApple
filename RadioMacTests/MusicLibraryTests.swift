import AVFoundation
import XCTest

@testable import RadioMac

/// Local music library: M3U parsing, folder scanning, playlists and the
/// metadata matching used by the online enrichment.
@MainActor
final class MusicLibraryTests: XCTestCase {

    // MARK: - Local music

    func testMusicPlaylistFileParsesM3U() {
        let text = """
        #EXTM3U
        #PLAYLIST:Вечерний джаз
        #EXTINF:213,Erik Satie - Gymnopédie No. 1
        /Music/satie.mp3
        #EXTINF:0,Bill Evans - Peace Piece
        tracks/local.m4a
        #EXTINF:-1 tvg-id="x",Radio Stream
        http://example.com/stream
        #EXTINF:-1,Windows file
        C:\\Music\\song.mp3
        """

        let parsed = MusicPlaylistFile.parse(text: text)
        XCTAssertEqual(parsed.name, "Вечерний джаз")
        XCTAssertEqual(parsed.entries.count, 4)
        XCTAssertEqual(parsed.entries[0].artist, "Erik Satie")
        XCTAssertEqual(parsed.entries[0].title, "Gymnopédie No. 1")
        XCTAssertEqual(parsed.entries[0].duration, 213)
        XCTAssertEqual(parsed.entries[1].title, "Peace Piece")
        XCTAssertNil(parsed.entries[1].duration)

        let base = URL(fileURLWithPath: "/Music/jazz/list.m3u")
        XCTAssertEqual(
            MusicPlaylistFile.resolvedURL(for: "tracks/local.m4a", relativeTo: base)?.path,
            "/Music/jazz/tracks/local.m4a"
        )
        XCTAssertNil(
            MusicPlaylistFile.resolvedURL(for: parsed.entries[2].location, relativeTo: base)
        )
        XCTAssertNil(
            MusicPlaylistFile.resolvedURL(for: parsed.entries[3].location, relativeTo: base)
        )
        XCTAssertEqual(
            MusicPlaylistFile.resolvedURL(for: "file:///Music/a%20b.mp3", relativeTo: base)?.path,
            "/Music/a b.mp3"
        )
    }

    func testMusicPlaylistFileExportsRoundTrip() {
        let tracks = [
            LocalTrack(path: "/Music/a.mp3", title: "First", artist: "Artist", duration: 61.4),
            LocalTrack(path: "/Music/b.flac", title: "Second", duration: nil),
        ]
        let data = MusicPlaylistFile.exportData(name: "Дачный микс", tracks: tracks)
        let parsed = MusicPlaylistFile.parse(data)

        XCTAssertEqual(parsed.name, "Дачный микс")
        XCTAssertEqual(parsed.entries.count, 2)
        XCTAssertEqual(parsed.entries[0].artist, "Artist")
        XCTAssertEqual(parsed.entries[0].title, "First")
        XCTAssertEqual(parsed.entries[0].duration, 61)
        XCTAssertEqual(parsed.entries[0].location, "/Music/a.mp3")
        XCTAssertNil(parsed.entries[1].duration)
        XCTAssertEqual(parsed.entries[1].location, "/Music/b.flac")
    }

    func testLocalFileNamesAndDurationFormatting() {
        let fallback = LocalAudioMetadata.fallback(
            from: URL(fileURLWithPath: "/Music/01 - Erik Satie - Gymnopedie No. 1.wav")
        )
        XCTAssertEqual(fallback.artist, "Erik Satie")
        XCTAssertEqual(fallback.title, "Gymnopedie No. 1")

        XCTAssertEqual(
            LocalAudioMetadata.fallback(
                from: URL(fileURLWithPath: "/Music/02. Clair de Lune.m4a")
            ).title,
            "Clair de Lune"
        )
        XCTAssertEqual(
            LocalAudioMetadata.fallback(
                from: URL(fileURLWithPath: "/Music/Unreleased Demo.mp3")
            ).artist,
            nil
        )

        XCTAssertEqual(LocalTrack.format(65), "1:05")
        XCTAssertEqual(LocalTrack.format(3_725), "1:02:05")
        XCTAssertNil(LocalTrack.format(nil))
        XCTAssertNil(LocalTrack.format(-4))

        XCTAssertEqual(LocalAudioMetadata.year(from: "2019-05-17T07:00:00Z"), 2_019)
        XCTAssertNil(LocalAudioMetadata.year(from: "12345"))
        XCTAssertEqual(LocalAudioMetadata.trackNumber(from: "3/12"), 3)
        XCTAssertNil(LocalAudioMetadata.trackNumber(from: "x"))
        XCTAssertEqual(LocalAudioMetadata.stripTrackPrefix("07 - Song"), "Song")
        XCTAssertEqual(LocalAudioMetadata.stripTrackPrefix("Song"), "Song")
    }

    func testTrackMatchScoresExactCandidatesHigher() {
        let query = TrackQuery(title: "Gymnopédie No. 1", artist: "Erik Satie", album: nil)
        let exact = TrackEnrichment(
            title: "Gymnopedie No. 1",
            artist: "Erik Satie",
            album: "Trois Gymnopedies",
            year: 1_888,
            genre: "Classical",
            artworkURL: "https://example.com/cover.jpg",
            source: "Test"
        )
        let different = TrackEnrichment(
            title: "Gymnopedie No. 3",
            artist: "Erik Satie",
            album: nil,
            source: "Test"
        )
        let otherArtist = TrackEnrichment(
            title: "Gymnopedie No. 1",
            artist: "Someone Else",
            album: nil,
            source: "Test"
        )

        XCTAssertEqual(TrackMatch.normalised("Gymnopédie No. 1 (Remastered)"), "gymnopedie no 1")
        XCTAssertEqual(TrackMatch.normalised("AC/DC"), "ac dc")
        XCTAssertGreaterThan(
            TrackMatch.score(query: query, candidate: exact),
            TrackMatch.score(query: query, candidate: different)
        )
        XCTAssertGreaterThan(
            TrackMatch.score(query: query, candidate: exact),
            TrackMatch.score(query: query, candidate: otherArtist)
        )
        XCTAssertGreaterThanOrEqual(
            TrackMatch.score(query: query, candidate: exact),
            TrackMatch.acceptThreshold
        )

        let track = LocalTrack(path: "/Music/a.mp3", title: "Gymnopedie No. 1")
        let changes = exact.changes(for: track)
        XCTAssertEqual(changes.artist, "Erik Satie")
        XCTAssertEqual(changes.album, "Trois Gymnopedies")
        XCTAssertEqual(changes.artworkURL, "https://example.com/cover.jpg")
        XCTAssertNil(changes.title, "an existing title is not replaced")

        var withArtist = track
        withArtist.artist = "Known"
        XCTAssertNil(exact.changes(for: withArtist).artist)
    }

    func testMusicLibraryImportsFilesAndManagesPlaylists() async throws {
        let folder = try makeMusicFolder(["01 - Test Artist - First Song.wav", "02. Second Song.wav"])
        let storage = folder.appendingPathComponent("library.json")
        let defaults = scratchDefaults()
        defaults.set(false, forKey: DefaultsKey.musicAutoEnrich)

        let library = MusicLibrary(storageURL: storage, defaults: defaults)
        let summary = await library.addFiles([folder])

        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(library.tracks.count, 2)
        XCTAssertEqual(library.sources.count, 1)

        let first = try XCTUnwrap(library.tracks.first(where: { $0.displayTitle == "First Song" }))
        XCTAssertEqual(first.displayArtist, "Test Artist")
        XCTAssertNotNil(first.duration)
        XCTAssertTrue(first.needsEnrichment, "album and artwork are missing")

        let playlist = try XCTUnwrap(library.createPlaylist(name: "Mix"))
        library.addTracks([first.id], to: playlist.id)
        library.addTracks([first.id], to: playlist.id)
        XCTAssertEqual(library.playlist(id: playlist.id)?.trackIDs, [first.id])

        XCTAssertEqual(library.tracks(in: playlist.id).map(\.id), [first.id])
        XCTAssertEqual(library.filteredTracks(query: "first", playlistID: nil, sort: .title).count, 1)

        library.renamePlaylist(id: playlist.id, name: "Вечер")
        XCTAssertEqual(library.playlist(id: playlist.id)?.name, "Вечер")

        let export = try XCTUnwrap(library.m3uData(for: playlist.id))
        XCTAssertEqual(MusicPlaylistFile.parse(export).entries.count, 1)

        library.flush()
        let reloaded = MusicLibrary(storageURL: storage, defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.tracks.count, 2)
        XCTAssertEqual(reloaded.playlists.first?.name, "Вечер")
        XCTAssertEqual(reloaded.sources.count, 1)

        library.removeTrack(id: first.id)
        XCTAssertTrue(library.tracks(in: playlist.id).isEmpty)
        XCTAssertEqual(library.tracks.count, 1)

        library.deletePlaylist(id: playlist.id)
        XCTAssertNil(library.playlist(id: playlist.id))
    }

    func testMusicLibraryImportsM3UAndSkipsStreams() async throws {
        let folder = try makeMusicFolder(["first.wav", "second.wav"])
        let playlistURL = folder.appendingPathComponent("mix.m3u")
        let text = """
        #EXTM3U
        #PLAYLIST:Домашний микс
        #EXTINF:1,Erik Satie - First
        first.wav
        #EXTINF:1,Erik Satie - Second
        second.wav
        #EXTINF:-1,Stream
        https://example.com/stream.mp3
        #EXTINF:-1,Missing
        missing.wav
        """
        try text.write(to: playlistURL, atomically: true, encoding: .utf8)

        let storage = folder.appendingPathComponent("library.json")
        let defaults = scratchDefaults()
        defaults.set(false, forKey: DefaultsKey.musicAutoEnrich)
        let library = MusicLibrary(storageURL: storage, defaults: defaults)

        let result = try await library.importPlaylist(from: playlistURL)
        XCTAssertEqual(result.name, "Домашний микс")
        XCTAssertEqual(result.addedTracks, 2)
        XCTAssertEqual(result.skippedEntries, 2)
        XCTAssertEqual(library.tracks.count, 2)
        XCTAssertEqual(library.tracks(in: result.playlistID).count, 2)
        XCTAssertEqual(
            library.tracks(in: result.playlistID).map(\.path),
            [folder.appendingPathComponent("first.wav").path,
             folder.appendingPathComponent("second.wav").path]
        )
        XCTAssertTrue(library.hasAccess(toFolder: folder))
    }

    func testMusicLibraryPersistsEnrichmentIntoLibraryOnly() async throws {
        let folder = try makeMusicFolder(["track.wav"])
        let storage = folder.appendingPathComponent("library.json")
        let defaults = scratchDefaults()
        defaults.set(false, forKey: DefaultsKey.musicAutoEnrich)
        let library = MusicLibrary(storageURL: storage, defaults: defaults)
        _ = await library.addFiles([folder.appendingPathComponent("track.wav")])

        let track = try XCTUnwrap(library.tracks.first)
        library.apply(
            TrackEnrichment(
                title: "Track",
                artist: "Artist",
                album: "Album",
                year: 2_020,
                genre: "Ambient",
                artworkURL: "https://example.com/art.jpg",
                source: "Test"
            ),
            to: track.id
        )
        let enriched = try XCTUnwrap(library.track(id: track.id))
        XCTAssertEqual(enriched.displayAlbum, "Album")
        XCTAssertEqual(enriched.displayArtist, "Artist")
        XCTAssertEqual(enriched.year, 2020)
        XCTAssertEqual(enriched.enrichmentSource, "Test")
        XCTAssertNotNil(enriched.enrichedAt)
        XCTAssertFalse(enriched.needsEnrichment)

        library.flush()
        let reloaded = MusicLibrary(storageURL: storage, defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.track(id: track.id)?.displayAlbum, "Album")
    }

    // MARK: - Helpers

    private func scratchDefaults() -> UserDefaults {
        let suite = "radio-mac.music-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeMusicFolder(_ names: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("radio-mac-music-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names {
            try writeSilentWav(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    private func writeSilentWav(to url: URL, seconds: Double = 1) throws {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        )
        buffer.frameLength = frames
        try file.write(from: buffer)
    }
}
