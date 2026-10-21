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

    func testDiagnosticsStoreAndRedaction() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("radiomac-diag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DiagnosticsStore(directory: directory, limitBytes: 10_000)
        let first = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(store.beginSession(now: first))
        store.append("2026-01-01T00:00:00Z [app] start")
        XCTAssertEqual(store.readLines(), ["2026-01-01T00:00:00Z [app] start"])

        let second = first.addingTimeInterval(60)
        let previous = store.beginSession(now: second)
        XCTAssertNotNil(previous)
        if let previous {
            XCTAssertEqual(previous.timeIntervalSince1970, first.timeIntervalSince1970, accuracy: 1)
        }

        store.endSession()
        XCTAssertNil(store.beginSession(now: second.addingTimeInterval(60)))
        store.clear()
        XCTAssertTrue(store.readLines().isEmpty)

        XCTAssertEqual(
            DiagnosticsService.redact("stream https://example.com/live.mp3?token=secret failed"),
            "stream https://example.com failed"
        )
        XCTAssertEqual(DiagnosticsService.redact("no urls here"), "no urls here")

        let line = DiagnosticsService.line(
            date: first,
            category: "error",
            message: "https://example.com/stream?x=1 timeout"
        )
        XCTAssertTrue(line.contains("[error]"))
        XCTAssertTrue(line.contains("https://example.com"))
        XCTAssertFalse(line.contains("x=1"))
    }

    func testAlarmScheduleAndFade() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let base = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 19, hour: 8, minute: 0)
        )!
        let weekday = calendar.component(.weekday, from: base)
        let alarm = AlarmSettings(
            enabled: true,
            hour: 9,
            minute: 0,
            weekdays: [weekday],
            stationID: "test-station",
            fadeInSeconds: 30
        )

        let today = alarm.nextFireDate(after: base, calendar: calendar)
        XCTAssertEqual(
            today,
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base)
        )

        let later = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: base)!
        let nextWeek = alarm.nextFireDate(after: later, calendar: calendar)
        XCTAssertEqual(
            nextWeek,
            calendar.date(byAdding: .day, value: 7, to: today!)
        )

        XCTAssertNil(
            AlarmSettings(
                enabled: false,
                hour: 9,
                minute: 0,
                weekdays: [weekday],
                stationID: nil,
                fadeInSeconds: 30
            ).nextFireDate(after: base, calendar: calendar)
        )
        XCTAssertNil(
            AlarmSettings(
                enabled: true,
                hour: 9,
                minute: 0,
                weekdays: [],
                stationID: nil,
                fadeInSeconds: 30
            ).nextFireDate(after: base, calendar: calendar)
        )

        guard let data = try? JSONEncoder().encode(alarm),
              let decoded = try? JSONDecoder().decode(AlarmSettings.self, from: data)
        else {
            return XCTFail("alarm settings roundtrip failed")
        }
        XCTAssertEqual(decoded, alarm)

        XCTAssertEqual(AlarmService.fadeVolume(target: 0.8, elapsed: 0, duration: 30), 0, accuracy: 0.0001)
        XCTAssertEqual(AlarmService.fadeVolume(target: 0.8, elapsed: 15, duration: 30), 0.4, accuracy: 0.0001)
        XCTAssertEqual(AlarmService.fadeVolume(target: 0.8, elapsed: 30, duration: 30), 0.8, accuracy: 0.0001)
        XCTAssertEqual(AlarmService.fadeVolume(target: 0.8, elapsed: 60, duration: 30), 0.8, accuracy: 0.0001)
        XCTAssertEqual(AlarmService.fadeVolume(target: 0.8, elapsed: 1, duration: 0), 0.8, accuracy: 0.0001)
    }

    func testStationGroupsPersistAndReorder() {
        let defaults = scratchDefaults()
        let library = StationLibrary(defaults: defaults)
        library.load()

        let morning = library.add(
            name: "Morning Show",
            url: "https://example.com/morning.mp3",
            genre: GenreCatalog.jazz,
            group: "alpha"
        )
        let evening = library.add(
            name: "Evening Show",
            url: "https://example.com/evening.mp3",
            genre: GenreCatalog.jazz,
            group: "beta"
        )
        let sameGroup = library.add(
            name: "Another Morning",
            url: "https://example.com/morning-2.mp3",
            genre: GenreCatalog.jazz,
            group: "ALPHA"
        )

        XCTAssertEqual(sameGroup.group, "alpha", "group casing should reuse the existing spelling")
        XCTAssertEqual(library.groups, ["alpha", "beta"])

        library.move(id: evening.id, before: morning.id)
        let ids = library.stations.map(\.id)
        XCTAssertLessThan(
            ids.firstIndex(of: evening.id) ?? .max,
            ids.firstIndex(of: morning.id) ?? .max
        )

        library.moveToEnd(id: evening.id)
        XCTAssertEqual(library.stations.last?.id, evening.id)

        let reloaded = StationLibrary(defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.byID(morning.id)?.group, "alpha")
        XCTAssertEqual(reloaded.stations.last?.id, evening.id)
    }

    func testGroupFilterAndReorderAvailability() {
        let defaults = scratchDefaults()
        let library = StationLibrary(defaults: defaults)
        library.load()
        let grouped = library.add(
            name: "Grouped",
            url: "https://example.com/grouped.mp3",
            genre: GenreCatalog.jazz,
            group: "Morning"
        )

        let model = MainViewModel(library: library)
        model.setFilter(.group("Morning"))
        XCTAssertEqual(model.visible.map(\.id), [grouped.id])
        XCTAssertFalse(model.canReorder, "reordering is disabled while a filter is active")

        model.setFilter(.all)
        XCTAssertTrue(model.canReorder)
        XCTAssertTrue(model.visible.contains { $0.id == grouped.id })
    }

    func testStreamInfoFormattingAndCodecs() {
        let stereo = StreamInfo(
            codec: "MP3",
            frequency: 44_100,
            channels: 2,
            bitrateKbps: 128,
            bufferMilliseconds: 500
        )
        XCTAssertEqual(stereo.sampleRateText, "44100 Гц")
        XCTAssertEqual(stereo.channelsText, "стерео")
        XCTAssertEqual(stereo.bitrateText, "128 кбит/с")
        XCTAssertEqual(stereo.bufferText, "500 мс")

        let unknown = StreamInfo(
            codec: "AAC",
            frequency: 0,
            channels: 1,
            bitrateKbps: nil,
            bufferMilliseconds: 0
        )
        XCTAssertEqual(unknown.sampleRateText, "—")
        XCTAssertEqual(unknown.channelsText, "моно")
        XCTAssertEqual(unknown.bitrateText, "—")
        XCTAssertEqual(unknown.bufferText, "—")

        XCTAssertEqual(StreamInfo.codecName(for: 0x10005), "MP3")
        XCTAssertEqual(StreamInfo.codecName(for: 0x10002), "OGG/Vorbis")
        XCTAssertEqual(StreamInfo.codecName(for: 0x1000b), "AAC")
        XCTAssertEqual(StreamInfo.codecName(for: 0x1000a), "Поток")
        XCTAssertEqual(StreamInfo.codecName(for: 0x99999), "Неизвестно")
    }
}
