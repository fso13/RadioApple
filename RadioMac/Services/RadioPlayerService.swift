import Combine
import Foundation
#if os(macOS)
import WidgetKit
#endif

/// Glue between the audio engine, the station library, track metadata and the
/// system Now Playing tile.
@MainActor
final class RadioPlayerService: ObservableObject {
    enum Status: String, Sendable {
        case idle, loading, playing, paused, reconnecting, error

        var isActive: Bool {
            switch self {
            case .playing, .paused, .loading, .reconnecting: return true
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
    @Published private(set) var activeEngineName = "AVPlayer"
    @Published private(set) var reconnectAttempts = 0

    /// Currently playing file from the local music library.
    @Published private(set) var localTrack: LocalTrack?
    /// Order used by the previous/next buttons while a local file plays.
    @Published private(set) var localQueue: [LocalTrack] = []
    @Published private(set) var localQueueTitle: String?
    @Published private(set) var playbackElapsed: Double = 0
    @Published private(set) var playbackDuration: Double?

    private let settings: AppSettings
    private let library: StationLibrary
    private let equalizer: EqualizerService
    private let nativeEngine = NativeAudioEngine()
    private let lookup = NowPlayingLookup.shared

    private var pollTimer: Timer?
    private var nowPlayingGeneration = 0
    private var icyLive = false
    private var cancellables: Set<AnyCancellable> = []
    private var wantsPlayback = false
    private var transientVolume: Double = 1
    private let reconnectPolicy = ReconnectPolicy()
    private var reconnectTask: Task<Void, Never>?
    private var stableTask: Task<Void, Never>?
    private var progressTimer: Timer?

    init(
        settings: AppSettings,
        library: StationLibrary,
        equalizer: EqualizerService
    ) {
        self.settings = settings
        self.library = library
        self.equalizer = equalizer
        self.volume = settings.volume
        wireEngine()
        observeLibrary()

        equalizer.$enabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.nativeEngine.setEQEnabled(enabled)
            }
            .store(in: &cancellables)

        equalizer.$gains
            .receive(on: RunLoop.main)
            .sink { [weak self] gains in
                self?.nativeEngine.setEQGains(gains)
            }
            .store(in: &cancellables)

        nativeEngine.setEQEnabled(equalizer.enabled)
        nativeEngine.setEQGains(equalizer.gains)

        Publishers.CombineLatest4($station, $status, $nowPlaying, $localTrack)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.publishSharedState()
            }
            .store(in: &cancellables)
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
        nativeEngine.setVolume(volume)
        if settings.resumeLastStation,
           let id = settings.lastStationID,
           let station = library.byID(id) {
            play(station)
        } else if let autoplay = library.stations.first(where: { $0.autoplay && $0.streamURL != nil }) {
            play(autoplay)
        }
    }

    private func wireEngine() {
        nativeEngine.onStateChange = { [weak self] state in
            self?.handleEngineState(state)
        }
        nativeEngine.onMetadata = { [weak self] raw in
            self?.handleICYTitle(raw)
        }
        nativeEngine.onPlaybackError = { [weak self] message in
            self?.errorMessage = message
            self?.handleEngineState(.error)
        }
        nativeEngine.onEnded = { [weak self] in
            self?.handleLocalEnded()
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

    func play(_ station: RadioStation, persist: Bool = true) {
        reconnectTask?.cancel()
        reconnectTask = nil
        stableTask?.cancel()
        stableTask = nil
        reconnectAttempts = 0
        wantsPlayback = true
        clearLocalPlayback()

        self.station = station
        nowPlaying = nil
        streamInfo = nil
        icyLive = false
        nowPlayingGeneration += 1
        errorMessage = nil
        status = .loading
        syncSystemNowPlaying()

        if persist {
            settings.setLastStationID(station.id)
        }
        if let presetID = station.eqPresetID,
           EqualizerCatalog.presets.contains(where: { $0.id == presetID }) {
            equalizer.applyPreset(presetID)
        }
        beginPlayback(station)
    }

    private func beginPlayback(_ station: RadioStation) {
        errorMessage = nil
        status = .loading
        restartNowPlayingPoll()

        guard let url = station.streamURL else {
            wantsPlayback = false
            status = .error
            errorMessage = "Некорректная ссылка на поток"
            stopNowPlayingPoll()
            return
        }

        nativeEngine.stop(emitIdle: false)
        activeEngineName = "AVPlayer"
        nativeEngine.setVolume(effectiveVolume(for: station))
        nativeEngine.play(url: url)
    }

    /// Manual retry from the error state.
    func retryNow() {
        if let localTrack {
            playLocal(localTrack, queue: localQueue, title: localQueueTitle)
            return
        }
        guard let station else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        stableTask?.cancel()
        stableTask = nil
        reconnectAttempts = 0
        wantsPlayback = true
        beginPlayback(station)
    }

    func togglePlayPause() {
        switch status {
        case .playing:
            pause()
        case .paused:
            resumeActive()
        default:
            if let localTrack {
                playLocal(localTrack, queue: localQueue, title: localQueueTitle)
            } else if let station {
                play(station)
            }
        }
    }

    func pause() {
        guard status == .playing else { return }
        wantsPlayback = false
        reconnectTask?.cancel()
        reconnectTask = nil
        stableTask?.cancel()
        stableTask = nil
        nativeEngine.pause()
    }

    func resumeOrPlay() {
        if status == .paused {
            resumeActive()
        } else if let localTrack {
            playLocal(localTrack, queue: localQueue, title: localQueueTitle)
        } else if let station {
            play(station)
        }
    }

    private func resumeActive() {
        wantsPlayback = true
        nativeEngine.resume()
    }

    func stop() {
        wantsPlayback = false
        reconnectAttempts = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        stableTask?.cancel()
        stableTask = nil
        stopNowPlayingPoll()
        clearLocalPlayback()
        nowPlayingGeneration += 1
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
        nativeEngine.setVolume(effectiveVolume(for: station))
        settings.setVolume(volume)
    }

    private func publishSharedState() {
        #if os(macOS)
        let state: SharedPlaybackState
        if let localTrack {
            state = SharedPlaybackState(
                stationID: localTrack.id,
                stationName: localQueueTitle ?? "Локальная музыка",
                track: localTrack.trayLine,
                isPlaying: status == .playing,
                updatedAt: Date()
            )
        } else {
            state = SharedPlaybackState(
                stationID: station?.id ?? "",
                stationName: station?.name ?? "",
                track: nowPlaying?.trayLine,
                isPlaying: status == .playing,
                updatedAt: Date()
            )
        }
        state.save()
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func effectiveVolume(for station: RadioStation?) -> Double {
        let offset = station?.volumeOffsetDB ?? 0
        let multiplier = pow(10, offset / 20)
        return min(1, max(0, volume * multiplier * transientVolume))
    }

    /// Sleep-timer fade. Not persisted: the user's volume returns after it ends.
    func setFadeFactor(_ factor: Double) {
        transientVolume = min(1, max(0, factor))
        nativeEngine.setVolume(effectiveVolume(for: station))
    }

    func consumeError() -> String? {
        defer { errorMessage = nil }
        return errorMessage
    }

    /// Re-reads the current stream properties (used by the diagnostics panel).
    func refreshStreamInfo() {
        refreshStreamInfoIfNeeded(force: true)
    }

    // MARK: - Local files

    var isLocalPlayback: Bool { localTrack != nil }

    var localTrackIndex: Int? {
        guard let localTrack else { return nil }
        return localQueue.firstIndex { $0.id == localTrack.id }
    }

    var canPlayNextLocalTrack: Bool {
        guard let index = localTrackIndex else { return false }
        return index + 1 < localQueue.count
    }

    var canPlayPreviousLocalTrack: Bool {
        guard let index = localTrackIndex else { return false }
        return index > 0
    }

    /// Plays a file from the local library. `queue` defines what the previous
    /// and next buttons do; `title` is what the menu bar and widget show.
    func playLocal(
        _ track: LocalTrack,
        queue: [LocalTrack]? = nil,
        title: String? = nil
    ) {
        if track.isMissing {
            errorMessage = "Файл не найден: \(track.fileName)"
            status = .error
            syncSystemNowPlaying()
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        stableTask?.cancel()
        stableTask = nil
        reconnectAttempts = 0
        wantsPlayback = true

        if let queue, !queue.isEmpty {
            localQueue = queue
        }
        if !localQueue.contains(where: { $0.id == track.id }) {
            localQueue = [track]
        }
        if let title {
            localQueueTitle = title
        }

        station = nil
        localTrack = track
        nowPlaying = NowPlaying(
            raw: track.trayLine,
            artist: track.displayArtist,
            title: track.displayTitle,
            album: track.displayAlbum,
            artworkURL: track.artworkURL,
            duration: track.duration
        )
        streamInfo = nil
        icyLive = false
        nowPlayingGeneration += 1
        errorMessage = nil
        playbackElapsed = 0
        playbackDuration = track.duration
        status = .loading
        startProgressTimer()
        syncSystemNowPlaying()

        nativeEngine.stop(emitIdle: false)
        activeEngineName = "AVPlayer"
        nativeEngine.setVolume(effectiveVolume(for: nil))
        nativeEngine.play(url: track.url)
    }

    /// Plays a list (album, playlist or search result) starting at `index`.
    func playLocalTracks(_ items: [LocalTrack], startingAt index: Int, title: String?) {
        guard items.indices.contains(index) else { return }
        playLocal(items[index], queue: items, title: title)
    }

    @discardableResult
    func playNextLocalTrack() -> Bool {
        guard let index = localTrackIndex, index + 1 < localQueue.count else { return false }
        playLocal(localQueue[index + 1], queue: localQueue, title: localQueueTitle)
        return true
    }

    @discardableResult
    func playPreviousLocalTrack() -> Bool {
        guard let index = localTrackIndex, index > 0 else { return false }
        playLocal(localQueue[index - 1], queue: localQueue, title: localQueueTitle)
        return true
    }

    /// Keeps the transport and Control Center in sync after an edit.
    func refreshLocalTrack(_ track: LocalTrack) {
        guard localTrack?.id == track.id else { return }
        localTrack = track
        if let duration = track.duration { playbackDuration = duration }
        nowPlaying = NowPlaying(
            raw: track.trayLine,
            artist: track.displayArtist,
            title: track.displayTitle,
            album: track.displayAlbum,
            artworkURL: track.artworkURL,
            duration: track.duration
        )
        syncSystemNowPlaying()
    }

    func seekLocal(toFraction fraction: Double) {
        guard isLocalPlayback, let duration = playbackDuration, duration > 0 else { return }
        let seconds = min(max(0, fraction), 1) * duration
        nativeEngine.seek(to: seconds)
        playbackElapsed = seconds
        syncSystemNowPlaying()
    }

    // MARK: - Local progress

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocalProgress() }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func refreshLocalProgress() {
        guard localTrack != nil else { return }
        guard status == .playing || status == .paused || status == .loading else { return }
        let elapsed = nativeEngine.currentTime
        if elapsed.isFinite, elapsed >= 0, abs(elapsed - playbackElapsed) > 0.05 {
            playbackElapsed = elapsed
        }
        if let duration = nativeEngine.duration, duration > 0, playbackDuration != duration {
            playbackDuration = duration
        }
    }

    private func handleLocalEnded() {
        guard localTrack != nil else { return }
        if playNextLocalTrack() { return }
        wantsPlayback = false
        stopProgressTimer()
        if let duration = playbackDuration { playbackElapsed = duration }
        status = .idle
        syncSystemNowPlaying()
    }

    private func clearLocalPlayback() {
        localTrack = nil
        localQueue = []
        localQueueTitle = nil
        playbackElapsed = 0
        playbackDuration = nil
        stopProgressTimer()
    }

    // MARK: - Engine events

    private func handleEngineState(_ state: RadioPlaybackState) {
        if handleLocalEngineState(state) { return }

        if state == .error {
            if wantsPlayback, station != nil {
                scheduleReconnect()
                return
            }
            status = .error
            if errorMessage == nil {
                errorMessage = "Не удалось открыть поток"
            }
            stopNowPlayingPoll()
            syncSystemNowPlaying()
            return
        }

        if state == .idle {
            if wantsPlayback, station != nil {
                scheduleReconnect()
                return
            }
            if status == .error { return }
        }

        let next = Status(rawValue: state.rawValue) ?? .idle
        if next == .playing {
            reconnectTask?.cancel()
            reconnectTask = nil
            scheduleStableReset()
            if errorMessage?.hasPrefix("Переподключение") == true {
                errorMessage = nil
            }
        }
        guard next != status else { return }
        status = next
        switch next {
        case .playing:
            refreshStreamInfoIfNeeded()
        case .idle, .error:
            streamInfo = nil
        case .loading, .paused, .reconnecting:
            break
        }
        syncSystemNowPlaying()
    }

    /// Returns true when a local file is the active source and the state was
    /// fully handled here.
    private func handleLocalEngineState(_ state: RadioPlaybackState) -> Bool {
        guard localTrack != nil else { return false }
        switch state {
        case .playing:
            reconnectAttempts = 0
            if status != .playing {
                status = .playing
                syncSystemNowPlaying()
            }
        case .loading:
            if status != .loading { status = .loading }
        case .paused:
            if !wantsPlayback, status != .paused {
                status = .paused
                syncSystemNowPlaying()
            }
        case .idle:
            // End of a file arrives through `onEnded`; anything else is an
            // explicit stop that the service already handles.
            if !wantsPlayback, status != .idle {
                status = .idle
                syncSystemNowPlaying()
            }
        case .reconnecting:
            break
        case .error:
            wantsPlayback = false
            status = .error
            if errorMessage == nil { errorMessage = "Не удалось открыть файл" }
            stopProgressTimer()
            syncSystemNowPlaying()
        }
        return true
    }

    private func scheduleReconnect() {
        guard wantsPlayback, let station else { return }
        guard reconnectTask == nil else { return }

        reconnectTask?.cancel()
        stableTask?.cancel()

        guard let delay = reconnectPolicy.delay(forAttempt: reconnectAttempts) else {
            wantsPlayback = false
            status = .error
            errorMessage = "Не удалось переподключиться. Проверьте сеть и нажмите «Повторить»."
            reconnectTask = nil
            stopNowPlayingPoll()
            syncSystemNowPlaying()
            return
        }

        reconnectAttempts += 1
        status = .reconnecting
        errorMessage = "Переподключение… \(reconnectAttempts)/\(reconnectPolicy.maxAttempts)"
        syncSystemNowPlaying()

        let stationID = station.id
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            guard self.wantsPlayback, self.station?.id == stationID else { return }
            self.beginPlayback(station)
        }
    }

    private func scheduleStableReset() {
        stableTask?.cancel()
        stableTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, !Task.isCancelled, self.status == .playing else { return }
            self.reconnectAttempts = 0
            if self.errorMessage?.hasPrefix("Переподключение") == true {
                self.errorMessage = nil
            }
        }
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
        nativeEngine.fetchStreamInfo(completion: completion)
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
        if let localTrack {
            guard status != .idle else {
                NowPlayingCenter.shared.clear()
                return
            }
            NowPlayingCenter.shared.update(
                title: localTrack.displayTitle,
                artist: localTrack.displayArtist ?? localTrack.displayAlbum ?? "Локальная музыка",
                album: localTrack.displayAlbum,
                artworkURL: localTrack.artworkURL,
                isPlaying: status == .playing,
                isLive: false,
                elapsed: playbackElapsed,
                duration: playbackDuration
            )
            return
        }

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
            album: track?.album,
            artworkURL: artwork,
            isPlaying: status == .playing,
            isLive: true
        )
    }
}
