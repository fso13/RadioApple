import XCTest

@testable import RadioMac

/// Ports the behaviour that was covered by `test/widget_test.dart` in the
/// Flutter build, plus a few checks for persistence and the shipped catalog.
final class RadioMacLogicTests: XCTestCase {
    // MARK: - Genres

    func testGenreCatalogNormalizesEmptyAndKnownNames() {
        XCTAssertEqual(GenreCatalog.normalize(""), GenreCatalog.other)
        XCTAssertEqual(GenreCatalog.normalize("   "), GenreCatalog.other)
        XCTAssertEqual(GenreCatalog.normalize("jazz"), GenreCatalog.jazz)
        XCTAssertEqual(GenreCatalog.normalize("SHANSON"), GenreCatalog.shanson)
        XCTAssertEqual(GenreCatalog.normalize("Synthwave"), "Synthwave")
    }

    func testStationReportsLogoAndCommentPresence() {
        let withLogo = RadioStation(
            id: "a",
            name: "Test",
            url: "https://example.com/stream",
            genre: GenreCatalog.rock,
            comment: "  hi  ",
            logoURL: "https://example.com/logo.png"
        )
        var withoutLogo = withLogo
        withoutLogo.logoURL = nil
        withoutLogo.comment = "   "

        XCTAssertTrue(withLogo.hasLogo)
        XCTAssertTrue(withLogo.hasComment)
        XCTAssertFalse(withoutLogo.hasLogo)
        XCTAssertFalse(withoutLogo.hasComment)
    }

    func testStationCodingRoundTripUsesFlutterKeys() throws {
        let station = RadioStation(
            id: "x",
            name: "Радио",
            url: "https://example.com/a.mp3",
            genre: "Rock",
            comment: nil,
            logoURL: "https://example.com/a.png",
            isFavorite: true,
            builtIn: true
        )
        let data = try JSONEncoder().encode(station)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["logoUrl"])
        XCTAssertNil(json["logoURL"])

        let decoded = try JSONDecoder().decode(RadioStation.self, from: data)
        XCTAssertEqual(decoded, station)
    }

    // MARK: - Logos

    func testLogoResolverKeepsBrandHostAndDropsCDNs() {
        XCTAssertEqual(LogoResolver.hostOf("https://ice1.somafm.com/groovesalad"), "ice1.somafm.com")
        XCTAssertEqual(LogoResolver.brandHost("ice1.somafm.com"), "somafm.com")
        XCTAssertNil(LogoResolver.brandHost("hostingradio.ru"))
        XCTAssertNil(LogoResolver.brandHost("stream.hostingradio.ru"))
        XCTAssertNil(LogoResolver.hostOf("not a url"))
    }

    // MARK: - Now playing

    func testNowPlayingParserSplitsArtistAndTitle() {
        let split = try? XCTUnwrap(NowPlayingParser.parse("Queen - Bohemian Rhapsody"))
        XCTAssertEqual(split?.artist, "Queen")
        XCTAssertEqual(split?.title, "Bohemian Rhapsody")
        XCTAssertEqual(split?.trayLine, "Queen — Bohemian Rhapsody")

        let icy = NowPlayingParser.parse("StreamTitle='Кино — Группа крови';StreamUrl='';")
        XCTAssertEqual(icy?.artist, "Кино")
        XCTAssertEqual(icy?.title, "Группа крови")

        XCTAssertNil(NowPlayingParser.parse(" - "))
        XCTAssertNil(NowPlayingParser.parse("Русское Радио", stationName: "Русское Радио"))
        XCTAssertNil(NowPlayingParser.parse("https://example.com/x"))
        XCTAssertNil(NowPlayingParser.parse("advert"))

        let titleOnly = NowPlayingParser.parse("Airwaves")
        XCTAssertNil(titleOnly?.artist)
        XCTAssertEqual(titleOnly?.displayTitle, "Airwaves")
    }

    func testImageURLDetection() {
        XCTAssertTrue(NowPlayingParser.looksLikeImageURL("https://x/y.PNG"))
        XCTAssertFalse(NowPlayingParser.looksLikeImageURL("https://x/status-json.xsl"))
        XCTAssertFalse(NowPlayingParser.looksLikeImageURL(nil))
    }

    // MARK: - Equalizer

    func testEqualizerCatalogKeepsTenBandsAndClampsGains() {
        XCTAssertEqual(EqualizerCatalog.presets.first?.id, EqualizerCatalog.flatID)
        for preset in EqualizerCatalog.presets {
            XCTAssertEqual(preset.gains.count, EqualizerCatalog.bandCount)
        }
        XCTAssertEqual(EqualizerCatalog.clampGains([40, -40]), [12, -12, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(EqualizerCatalog.label(forHz: 1_000), "1k")
        XCTAssertEqual(EqualizerCatalog.label(forHz: 125), "125")
        XCTAssertTrue(EqualizerCatalog.sameGains([1, 2], [1.01, 2]))
        XCTAssertFalse(EqualizerCatalog.sameGains([1, 2], [1.2, 2]))
    }

    // MARK: - Shipped catalog

    func testDefaultCatalogIsWellFormed() {
        let catalog = DefaultStations.catalog
        XCTAssertEqual(catalog.count, 47)
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count, "station ids must be unique")
        for station in catalog {
            XCTAssertFalse(station.id.isEmpty)
            XCTAssertFalse(station.name.isEmpty)
            XCTAssertNotNil(station.streamURL, "\(station.name) has an unusable URL")
            XCTAssertTrue(station.builtIn)
        }
        XCTAssertTrue(catalog.contains { $0.genre == GenreCatalog.news })
        XCTAssertTrue(catalog.contains { $0.genre == GenreCatalog.rock })
    }

    // MARK: - Persistence & migration

    private func scratchDefaults() -> UserDefaults {
        let suite = "radio-mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testPreferencesMigratorImportsFlutterKeysOnce() {
        let defaults = scratchDefaults()
        defaults.set(0.42, forKey: DefaultsKey.flutterPrefix + DefaultsKey.volume)
        defaults.set("rock-maximum", forKey: DefaultsKey.flutterPrefix + DefaultsKey.lastStationID)
        defaults.set(true, forKey: DefaultsKey.flutterPrefix + DefaultsKey.eqEnabled)
        defaults.set("[1,2,3]", forKey: DefaultsKey.flutterPrefix + DefaultsKey.eqGains)
        defaults.set("[]", forKey: DefaultsKey.flutterPrefix + DefaultsKey.stations)

        PreferencesMigrator.migrateIfNeeded(defaults)

        XCTAssertEqual(defaults.doubleLike(DefaultsKey.volume), 0.42)
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.lastStationID), "rock-maximum")
        XCTAssertEqual(defaults.boolLike(DefaultsKey.eqEnabled), true)
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.eqGains), "[1,2,3]")
        XCTAssertTrue(defaults.bool(forKey: DefaultsKey.migrationFlag))

        // A second run must not overwrite values the native app has since changed.
        defaults.set(0.9, forKey: DefaultsKey.volume)
        PreferencesMigrator.migrateIfNeeded(defaults)
        XCTAssertEqual(defaults.doubleLike(DefaultsKey.volume), 0.9)
    }

    func testSettingsRoundTripThroughUserDefaults() {
        let defaults = scratchDefaults()
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.volume, 0.8, accuracy: 0.0001)

        settings.setVolume(1.7)
        settings.setResumeLastStation(true)
        settings.setLastStationID("abc")
        settings.setAutoStartEnabled(true)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.volume, 1.0, accuracy: 0.0001)
        XCTAssertTrue(reloaded.resumeLastStation)
        XCTAssertEqual(reloaded.lastStationID, "abc")
        XCTAssertTrue(reloaded.autoStartEnabled)
    }

    func testStationLibrarySeedsEditsAndPersists() {
        let defaults = scratchDefaults()
        let library = StationLibrary(defaults: defaults)
        library.load()
        XCTAssertEqual(library.stations.count, DefaultStations.catalog.count)
        XCTAssertTrue(library.genres.contains(GenreCatalog.rock))
        XCTAssertEqual(library.genres.first, GenreCatalog.jazz)

        let added = library.add(
            name: "  Моя волна ",
            url: " https://example.com/live ",
            genre: "synthwave",
            comment: "  ",
            logoURL: "https://example.com/logo.png"
        )
        XCTAssertEqual(added.name, "Моя волна")
        XCTAssertEqual(added.url, "https://example.com/live")
        XCTAssertEqual(added.genre, "synthwave")
        XCTAssertNil(added.comment)
        XCTAssertTrue(added.hasLogo)

        library.toggleFavorite(id: added.id)
        XCTAssertTrue(library.byID(added.id)?.isFavorite == true)

        let reloaded = StationLibrary(defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.stations.count, DefaultStations.catalog.count + 1)
        XCTAssertEqual(reloaded.byID(added.id)?.genre, "synthwave")

        reloaded.remove(id: added.id)
        XCTAssertNil(reloaded.byID(added.id))
    }

    func testRestoreDefaultsKeepsCustomStationsAndFavourites() {
        let defaults = scratchDefaults()
        let library = StationLibrary(defaults: defaults)
        library.load()

        let custom = library.add(
            name: "Custom",
            url: "https://example.com/custom.mp3",
            genre: GenreCatalog.jazz
        )
        let builtInID = DefaultStations.catalog[0].id
        library.toggleFavorite(id: builtInID)

        library.restoreDefaults()

        XCTAssertEqual(library.stations.count, DefaultStations.catalog.count + 1)
        XCTAssertEqual(library.byID(custom.id)?.name, "Custom")
        XCTAssertEqual(library.byID(builtInID)?.isFavorite, true)
    }

    func testEmptyStationsJSONFallsBackToCatalog() {
        let defaults = scratchDefaults()
        defaults.set("garbage", forKey: DefaultsKey.stations)
        let library = StationLibrary(defaults: defaults)
        library.load()
        XCTAssertEqual(library.stations.count, DefaultStations.catalog.count)
    }
}
