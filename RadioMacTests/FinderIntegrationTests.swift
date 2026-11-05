import XCTest

@testable import RadioMac

/// The rules behind the Finder context menu and the payload the Finder Sync
/// extension hands to the app.
@MainActor
final class FinderIntegrationTests: XCTestCase {
    // MARK: - Context menu

    func testAudioSelectionPlansPlayback() throws {
        let root = try makeRoot()
        let mp3 = makeFile("one.mp3", in: root)
        let flac = makeFile("two.flac", in: root)

        let single = try XCTUnwrap(FinderMenuPlanner.plan(for: [mp3]))
        XCTAssertEqual(single.action, .playAudio)
        XCTAssertEqual(single.urls, [mp3])

        let multiple = try XCTUnwrap(FinderMenuPlanner.plan(for: [mp3, flac]))
        XCTAssertEqual(multiple.action, .playAudio)
        XCTAssertEqual(multiple.urls, [mp3, flac], "the Finder order is the queue order")
    }

    func testFolderSelectionPlansPlaylist() throws {
        let root = try makeRoot()
        let folder = makeFolder("Джаз", in: root)

        let plan = try XCTUnwrap(FinderMenuPlanner.plan(for: [folder]))
        XCTAssertEqual(plan.action, .createPlaylist)
        XCTAssertEqual(plan.urls, [folder])
    }

    func testSelectionsRadioMacCannotHandleHaveNoMenu() throws {
        let root = try makeRoot()
        let folder = makeFolder("Music", in: root)
        let otherFolder = makeFolder("Other", in: root)
        let mp3 = makeFile("one.mp3", in: root)

        XCTAssertNil(FinderMenuPlanner.plan(for: []))
        XCTAssertNil(FinderMenuPlanner.plan(for: [folder, otherFolder]))
        XCTAssertNil(FinderMenuPlanner.plan(for: [folder, mp3]))
        XCTAssertNil(FinderMenuPlanner.plan(for: [makeFile("cover.jpg", in: root)]))
        XCTAssertNil(FinderMenuPlanner.plan(for: [makeFile("list.m3u", in: root)]))
        XCTAssertNil(FinderMenuPlanner.plan(for: [URL(string: "https://example.com/a.mp3")!]))
    }

    func testMenuTitlesMatchLocalizationKeys() {
        XCTAssertEqual(FinderAction.playAudio.menuTitleKey, "Проиграть в RadioMac")
        XCTAssertEqual(FinderAction.createPlaylist.menuTitleKey, "Создать плейлист в RadioMac")
    }

    func testAudioFileTypesCoverTheLibrary() {
        // The extension and the library must agree on what an audio file is.
        XCTAssertEqual(LocalAudioMetadata.supportedExtensions, AudioFileTypes.supportedExtensions)
        XCTAssertTrue(AudioFileTypes.isSupported(URL(fileURLWithPath: "/Music/a.MP3")))
        XCTAssertFalse(AudioFileTypes.isSupported(URL(fileURLWithPath: "/Music/a.jpg")))
    }

    // MARK: - Extension payload

    func testFinderRequestRoundTrips() throws {
        let request = FinderRequest(
            action: .createPlaylist,
            paths: ["/Users/me/Music/Джаз", "/Users/me/Music/Рок"]
        )
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(FinderRequest.self, from: data), request)
    }

    func testBridgeReadsRequestFromNotificationPayload() throws {
        let request = FinderRequest(action: .playAudio, paths: ["/Users/me/Music/a.mp3"])
        let data = try JSONEncoder().encode(request)

        XCTAssertEqual(FinderBridge.request(from: [FinderBridge.requestKey: data]), request)
        XCTAssertNil(FinderBridge.request(from: nil))
        XCTAssertNil(FinderBridge.request(from: [FinderBridge.requestKey: "not data"]))
    }

    // MARK: - Library

    func testFolderPlaylistIsCreatedOnceAndRefreshed() throws {
        let library = MusicLibrary(storageURL: nil, defaults: scratchDefaults())
        library.tracks = [
            LocalTrack(path: "/Music/Jazz/a.mp3", title: "A"),
            LocalTrack(path: "/Music/Jazz/b.mp3", title: "B"),
        ]
        let folderPath = "/Music/Jazz"
        let playlist = try XCTUnwrap(
            library.createPlaylist(
                name: "Jazz",
                trackIDs: library.tracks.map(\.id),
                folderPath: folderPath
            )
        )
        XCTAssertEqual(playlist.folderPath, folderPath)
        XCTAssertEqual(library.tracks(in: playlist.id).map(\.displayTitle), ["A", "B"])

        // A second run refreshes the same playlist instead of «Jazz 2».
        library.replaceTracks([library.tracks[1].id], in: playlist.id)
        XCTAssertEqual(library.playlists.count, 1)
        XCTAssertEqual(library.tracks(in: playlist.id).map(\.displayTitle), ["B"])
        XCTAssertEqual(library.playlists.first?.folderPath, folderPath)
    }

    func testPlaylistDecodesWithoutFolderPath() throws {
        let json = """
        {"id":"1","name":"Jazz","trackIDs":[],"createdAt":0,"updatedAt":0}
        """
        let playlist = try JSONDecoder().decode(MusicPlaylist.self, from: Data(json.utf8))
        XCTAssertNil(playlist.folderPath)
    }

    func testLibraryFindsTrackByPath() {
        let library = MusicLibrary(storageURL: nil, defaults: scratchDefaults())
        library.tracks = [
            LocalTrack(path: "/Music/a.mp3", title: "A"),
            LocalTrack(path: "/Music/b.flac", title: "B"),
        ]

        XCTAssertEqual(library.track(atPath: "/Music/b.flac")?.displayTitle, "B")
        XCTAssertNil(library.track(atPath: "/Music/missing.mp3"))
    }

    // MARK: - Helpers

    /// A fresh temporary folder that is removed when the test ends.
    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("finder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeFile(_ name: String, in root: URL) -> URL {
        let url = root.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    private func makeFolder(_ name: String, in root: URL) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func scratchDefaults() -> UserDefaults {
        let suite = "FinderIntegrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
