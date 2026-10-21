import Combine
import Foundation

/// Glue between the audio engine, the station library, track metadata and the
/// system Now Playing tile.
@MainActor
final class RadioPlayerService: ObservableObject {
    enum Status: String, Sendable {
        case idle, loading, playing, paused, error

        var isActive: Bool {
            switch self {
            case .playing, .paused, .loading: return true
            case .idle, .error: return false
            }
        }
    }

    @Published private(set) var station: RadioStation?
    @Published private(set) var status: Status = .idle
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var streamInfo: StreamInfo?
    @Published private(set) var errorMessage: String?
    @Published private(set) var volume: Double
    @Published private(set) var activeEngineName = "BASS"

    private enum AudioEngineKind {
        case bass
        case native
    }

    private let settings: AppSettings
    private let library: StationLibrary
    private let equalizer: EqualizerService
    private let bassEngine: RadioEngine
    private let nativeEngine = NativeAudioEngine()
    private var activeEngine: AudioEngineKind?
    private let lookup = NowPlayingLookup.shared

    private var pollTimer: Timer?
    private var nowPlayingGeneration = 0
    private var icyLive = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings,
        library: StationLibrary,
        equalizer: EqualizerService,
        engine: RadioEngine = .shared
    ) {
        self.settings = settings
        self.library = library
        self.equalizer = equalizer
        self.bassEngine = engine
        self.volume = settings.volume
        wireEngine()
        observeLibrary()
        NowPlayingCenter.shared.configure(
            onPlay: { [weak self] in self?.resumeOrPlay() },
            onPause: { [weak self] in self?.pause() },
            onToggle: { [weak self] in self?.togglePlayPause() }
        )
    }

    // MARK: - Derived

    var isPlaying: Bool { status == .playing }
    var isActive: Bool { status.isActive }
    var trackTitle: String? { nowPlaying?.trayLine }

    // MARK: - Lifecycle

    func start() {
        bassEngine.setVolume(volume)
        nativeEngine.setVolume(volume)
        if settings.resumeLastStation,
           let id = settings.lastStationID,
           let station = library.byID(id) {
            play(station)
        }
    }

    private func wireEngine() {
        bassEngine.onStateChange = { [weak self] state in
            self?.handleEngineState(state, from: .bass)
        }
        bassEngine.onICYTitle = { [weak self] title in
            guard let self, self.activeEngine == .bass else { return }
            self.handleICYTitle(title)
        }
        bassEngine.onICYURL = { [weak self] url in
            guard let self, self.activeEngine == .bass else { return }
            self.handleICYURL(url)
        }
        bassEngine.onPlaybackError = { [weak self] message in
            guard let self, self.activeEngine == .bass else { return }
            self.errorMessage = message
        }

        nativeEngine.onStateChange = { [weak self] state in
            self?.handleEngineState(state, from: .native)
        }
        nativeEngine.onPlaybackError = { [weak self] message in
            guard let self, self.activeEngine == .native else { return }
            self.errorMessage = message
            self.handleEngineState(.error, from: .native)
        }
    }

    private func observeLibrary() {
        library.$stations
            .receive(on: RunLoop.main)
            .sink { [weak self] stations in
                self?.syncStationFromLibrary(stations)
            }
            .store(in: &cancellables)
    }

    // MARK: - Transport

    func play(_ station: RadioStation) {
        self.station = station
        nowPlaying = nil
        streamInfo = nil
        icyLive = false
        nowPlayingGeneration += 1
        errorMessage = nil
        status = .loading
        syncSystemNowPlaying()

        settings.setLastStationID(station.id)
        restartNowPlayingPoll()

        guard let url = station.streamURL else {
            status = .error
            errorMessage = "Некорректная ссылка на поток"
            stopNowPlayingPoll()
            return
        }

        let kind: AudioEngineKind = settings.audioEnginePreference.prefersNative(for: url)
            ? .native
            : .bass
        activeEngine = nil
        bassEngine.stop()
        nativeEngine.stop()
        activeEngine = kind
        activeEngineName = kind == .native ? "AVPlayer" : "BASS"

        switch kind {
        case .bass:
            bassEngine.setVolume(volume)
            bassEngine.play(url: url)
        case .native:
            nativeEngine.setVolume(volume)
            nativeEngine.play(url: url)
        }
    }

    func togglePlayPause() {
        switch status {
        case .playing:
            pause()
        case .paused:
            resumeActive()
        default:
            if let station { play(station) }
        }
    }

    func pause() {
        guard status == .playing else { return }
        switch activeEngine {
        case .bass: bassEngine.pause()
        case .native: nativeEngine.pause()
        case nil: break
        }
    }

    func resumeOrPlay() {
        if status == .paused {
            resumeActive()
        } else if let station {
            play(station)
        }
    }

    private func resumeActive() {
        switch activeEngine {
        case .bass: bassEngine.resume()
        case .native: nativeEngine.resume()
        case nil:
            if let station { play(station) }
        }
    }

    func stop() {
        stopNowPlayingPoll()
        nowPlayingGeneration += 1
        activeEngine = nil
        bassEngine.stop()
        nativeEngine.stop()
        status = .idle
        nowPlaying = nil
        streamInfo = nil
        icyLive = false
        errorMessage = nil
        syncSystemNowPlaying()
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        bassEngine.setVolume(volume)
        nativeEngine.setVolume(volume)
        settings.setVolume(volume)
    }

    func consumeError() -> String? {
        defer { errorMessage = nil }
        return errorMessage
    }

    /// Re-reads the current stream properties (used by the diagnostics panel).
    func refreshStreamInfo() {
        refreshStreamInfoIfNeeded(force: true)
    }

    // MARK: - Engine events

    private func handleEngineState(
        _ state: RadioPlaybackState,
        from kind: AudioEngineKind
    ) {
        guard activeEngine == kind else { return }
        let next = Status(rawValue: state.rawValue) ?? .idle
        // Keep the error banner until the user dismisses or retries.
        if next == .idle, status == .error { return }
        if next == .error, errorMessage == nil {
            errorMessage = "Не удалось открыть поток"
        }
        guard next != status else { return }
        status = next
        switch next {
        case .playing:
            refreshStreamInfoIfNeeded()
        case .idle, .error:
            streamInfo = nil
        case .loading, .paused:
            break
        }
        if next == .error { stopNowPlayingPoll() }
        syncSystemNowPlaying()
    }

    private func refreshStreamInfoIfNeeded(force: Bool = false) {
        guard let station else {
            streamInfo = nil
            return
        }
        guard force || streamInfo == nil else { return }

        let stationID = station.id
        let completion: @MainActor (StreamInfo?) -> Void = { [weak self] info in
            guard let self, self.station?.id == stationID else { return }
            self.streamInfo = info
        }
        switch activeEngine {
        case .native:
            nativeEngine.fetchStreamInfo(completion: completion)
        case .bass, nil:
            bassEngine.fetchStreamInfo(completion: completion)
        }
    }

    private func handleICYTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        applyNowPlaying(
            NowPlayingParser.parse(trimmed, stationName: station?.name),
            fromICY: true
        )
    }

    private func handleICYURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if NowPlayingParser.looksLikeImageURL(trimmed), nowPlaying != nil {
            applyNowPlaying(nowPlaying, artworkURL: trimmed)
        } else if let station {
            library.resolveFromHomepage(id: station.id, homepage: trimmed)
        }
    }

    private func syncStationFromLibrary(_ stations: [RadioStation]) {
        guard let current = station,
              let fresh = stations.first(where: { $0.id == current.id })
        else { return }
        guard fresh.logoURL != current.logoURL else { return }
        var updated = current
        updated.logoURL = fresh.logoURL
        station = updated
        syncSystemNowPlaying()
    }

    // MARK: - Track metadata

    private func restartNowPlayingPoll() {
        stopNowPlayingPoll()
        pollNowPlaying()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollNowPlaying() }
        }
    }

    private func stopNowPlayingPoll() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollNowPlaying() {
        guard let station else { return }
        guard status == .playing || status == .loading else { return }

        let generation = nowPlayingGeneration
        let allowICY = !icyLive
        Task { [weak self] in
            guard let self else { return }
            let track = await self.lookup.resolve(
                streamURL: station.url,
                stationName: station.name,
                allowICY: allowICY
            )
            await MainActor.run {
                guard generation == self.nowPlayingGeneration else { return }
                self.applyNowPlaying(track)
            }
        }
    }

    private func applyNowPlaying(
        _ track: NowPlaying?,
        fromICY: Bool = false,
        artworkURL: String? = nil
    ) {
        guard let track else { return }
        if fromICY { icyLive = true }

        let art = artworkURL ?? track.artworkURL
        if nowPlaying?.raw == track.raw {
            if let art, nowPlaying?.hasArtwork == false {
                var updated = nowPlaying
                updated?.artworkURL = art
                nowPlaying = updated
                syncSystemNowPlaying()
            }
            return
        }

        var next = track
        next.artworkURL = art
        nowPlaying = next
        syncSystemNowPlaying()
        fillArtwork()
    }

    private func fillArtwork() {
        guard let current = nowPlaying, !current.hasArtwork else { return }
        if station?.genre == GenreCatalog.news { return }
        let generation = nowPlayingGeneration

        Task { [weak self] in
            guard let self else { return }
            guard let art = await self.lookup.artworkFor(current) else { return }
            await MainActor.run {
                guard generation == self.nowPlayingGeneration,
                      self.nowPlaying?.raw == current.raw
                else { return }
                self.nowPlaying?.artworkURL = art
                self.syncSystemNowPlaying()
            }
        }
    }

    // MARK: - System Now Playing

    private func syncSystemNowPlaying() {
        guard let station, status != .idle else {
            NowPlayingCenter.shared.clear()
            return
        }

        let track = nowPlaying
        let title = track?.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let stationName = station.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDistinctTrack = (title?.isEmpty == false)
            && title?.lowercased() != stationName.lowercased()

        let nowTitle = hasDistinctTrack ? (title ?? stationName) : stationName
        let nowArtist: String
        if hasDistinctTrack, let artist = track?.displayArtist, !artist.isEmpty {
            nowArtist = artist
        } else {
            nowArtist = hasDistinctTrack ? stationName : "RadioMac"
        }

        let artwork = (track?.hasArtwork == true ? track?.artworkURL : nil) ?? station.logoURL

        NowPlayingCenter.shared.update(
            title: nowTitle,
            artist: nowArtist,
            artworkURL: artwork,
            isPlaying: status == .playing,
            isLive: true
        )
    }
}
