import Foundation

/// Playback state as reported by the audio engine.
enum RadioPlaybackState: String {
    case idle
    case loading
    case playing
    case paused
    case error
}

// MARK: - BASS sync callbacks

private func bassMetaSyncCallback(
    _ handle: HSYNC,
    _ channel: DWORD,
    _ data: DWORD,
    _ user: UnsafeMutableRawPointer?
) {
    guard let user else { return }
    let engine = Unmanaged<RadioEngine>.fromOpaque(user).takeUnretainedValue()
    engine.queue.async { engine.handleMetaSync() }
}

private func bassStallSyncCallback(
    _ handle: HSYNC,
    _ channel: DWORD,
    _ data: DWORD,
    _ user: UnsafeMutableRawPointer?
) {
    guard let user else { return }
    let engine = Unmanaged<RadioEngine>.fromOpaque(user).takeUnretainedValue()
    engine.queue.async { engine.handleStallSync(stalled: data == 0) }
}

private func bassEndSyncCallback(
    _ handle: HSYNC,
    _ channel: DWORD,
    _ data: DWORD,
    _ user: UnsafeMutableRawPointer?
) {
    guard let user else { return }
    let engine = Unmanaged<RadioEngine>.fromOpaque(user).takeUnretainedValue()
    engine.queue.async { engine.handleEndSync() }
}

/// Internet radio playback on top of the BASS library (un4seen).
///
/// A single serial queue owns every BASS handle; state changes are forwarded to
/// the main queue through the `on…` closures so SwiftUI can observe them.
final class RadioEngine: @unchecked Sendable {
    static let shared = RadioEngine()

    var onStateChange: ((RadioPlaybackState) -> Void)?
    var onICYTitle: ((String) -> Void)?
    var onICYURL: ((String) -> Void)?
    var onPlaybackError: ((String) -> Void)?

    /// Set once during initialisation; BASS_FX is required for the equalizer.
    var isEqualizerAvailable: Bool { fxAvailable }

    fileprivate let queue = DispatchQueue(label: "radio_mac.bass")
    private let streamLock = NSLock()
    private let eqLock = NSLock()

    private var stream: HSTREAM = 0
    private var requestCounter = 0
    private var wantsPlayback = false
    private var paused = false
    private var volume: Float = 0.8
    private var bassReady = false
    private var pluginsLoaded = false
    private var fxAvailable = false
    private var eqHandle: HFX = 0

    private var eqEnabled = false
    private var gains: [Float] = Array(repeating: 0, count: 10)

    private static let frequencies: [Float] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000,
    ]

    init() {
        initializeBass()
    }

    deinit {
        queue.sync {
            freeStream()
            if bassReady {
                BASS_Free()
                bassReady = false
            }
        }
    }

    // MARK: - Public API

    func play(url: URL) {
        queue.async { [weak self] in self?.startPlayback(url: url) }
    }

    func pause() {
        queue.async { [weak self] in
            guard let self, self.stream != 0 else { return }
            if BASS_ChannelPause(self.stream) != 0 {
                self.paused = true
                self.emitState(.paused)
            }
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self, self.stream != 0 else { return }
            if BASS_ChannelPlay(self.stream, 0) != 0 {
                self.paused = false
                self.wantsPlayback = true
                self.emitState(.playing)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in self?.stopPlayback(emitIdle: true) }
    }

    func setVolume(_ value: Double) {
        volume = max(0, min(1, Float(value)))
        queue.async { [weak self] in self?.applyVolume() }
    }

    func setEQEnabled(_ enabled: Bool) {
        eqLock.lock()
        eqEnabled = enabled
        eqLock.unlock()
        queue.async { [weak self] in self?.setupEQOnStream() }
    }

    func setEQGains(_ values: [Double]) {
        eqLock.lock()
        for index in 0..<min(gains.count, values.count) {
            gains[index] = max(-12, min(12, Float(values[index])))
        }
        eqLock.unlock()
        queue.async { [weak self] in self?.setupEQOnStream() }
    }

    var currentState: RadioPlaybackState {
        streamLock.lock()
        let activeStream = stream
        streamLock.unlock()
        guard activeStream != 0 else { return wantsPlayback ? .loading : .idle }
        if paused { return .paused }
        switch BASS_ChannelIsActive(activeStream) {
        case DWORD(BASS_ACTIVE_PLAYING): return .playing
        case DWORD(BASS_ACTIVE_PAUSED): return .paused
        case DWORD(BASS_ACTIVE_STALLED): return .loading
        default: return wantsPlayback ? .loading : .idle
        }
    }

    /// Reads the current stream's audio properties on the BASS queue.
    func fetchStreamInfo(completion: @escaping @MainActor (StreamInfo?) -> Void) {
        queue.async { [weak self] in
            guard let self, self.stream != 0 else {
                Task { @MainActor in completion(nil) }
                return
            }

            var info = BASS_CHANNELINFO()
            guard BASS_ChannelGetInfo(self.stream, &info) != 0 else {
                Task { @MainActor in completion(nil) }
                return
            }

            var bitrate: Float = 0
            let hasBitrate = BASS_ChannelGetAttribute(
                self.stream,
                DWORD(BASS_ATTRIB_BITRATE),
                &bitrate
            ) != 0

            let snapshot = StreamInfo(
                codec: StreamInfo.codecName(for: info.ctype),
                frequency: Int(info.freq),
                channels: Int(info.chans),
                bitrateKbps: hasBitrate && bitrate > 0 ? Int(bitrate.rounded()) : nil,
                bufferMilliseconds: Int(BASS_GetConfig(DWORD(BASS_CONFIG_BUFFER)))
            )
            Task { @MainActor in completion(snapshot) }
        }
    }

    // MARK: - Setup

    private func initializeBass() {
        guard !bassReady else { return }
        let version = BASS_GetVersion()
        let apiVersion = (version >> 16) & 0xffff
        guard apiVersion == BASSVERSION else {
            NSLog("RadioMac: incorrect BASS library version")
            return
        }
        guard BASS_Init(-1, 44_100, 0, nil, nil) != 0 else {
            NSLog("RadioMac: BASS_Init failed (%d)", BASS_ErrorGetCode())
            return
        }
        BASS_SetConfig(DWORD(BASS_CONFIG_NET_PLAYLIST), 1)
        BASS_SetConfig(DWORD(BASS_CONFIG_NET_TIMEOUT), 15_000)
        loadPlugins()
        bassReady = true
        applyVolume()
    }

    private func pluginPath(_ name: String) -> String? {
        var candidates: [URL] = []
        if let frameworks = Bundle.main.privateFrameworksURL {
            candidates.append(frameworks.appendingPathComponent(name))
        }
        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Frameworks")
                .appendingPathComponent(name)
        )
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        return nil
    }

    private func loadPlugins() {
        guard !pluginsLoaded else { return }
#if DEBUG
        for name in ["libbass_aac.dylib", "libbass_fx.dylib"] {
            guard let path = pluginPath(name) else {
                DebugLog.write("plugin missing: \(name)")
                continue
            }
            if let handle = dlopen(path, RTLD_NOW) {
                DebugLog.write("plugin dlopen ok: \(path)")
                dlclose(handle)
            } else if let error = dlerror() {
                DebugLog.write("plugin dlopen failed: \(path) -> \(String(cString: error))")
            }
        }
#endif
        if let path = pluginPath("libbass_aac.dylib") {
            if BASS_PluginLoad(path, 0) != 0 {
                NSLog("RadioMac: BASS_AAC loaded")
            } else {
                NSLog("RadioMac: BASS_AAC unavailable (%d)", BASS_ErrorGetCode())
            }
        }
        if let path = pluginPath("libbass_fx.dylib") {
            if BASS_PluginLoad(path, 0) != 0 {
                fxAvailable = true
                NSLog("RadioMac: BASS_FX loaded")
            } else {
                NSLog("RadioMac: BASS_FX unavailable (%d)", BASS_ErrorGetCode())
            }
        }
        pluginsLoaded = true
    }

    // MARK: - Equalizer

    private func setupEQOnStream() {
        guard stream != 0 else { return }
        removeEQFromStream()

        eqLock.lock()
        let enabled = eqEnabled
        let currentGains = gains
        eqLock.unlock()

        guard enabled, fxAvailable else { return }

        eqHandle = BASS_ChannelSetFX(stream, DWORD(BASS_FX_BFX_PEAKEQ), 0)
        guard eqHandle != 0 else {
            NSLog("RadioMac: EQ FX failed (%d)", BASS_ErrorGetCode())
            return
        }

        for index in 0..<min(currentGains.count, Self.frequencies.count) {
            applyEQBand(index: index, gain: currentGains[index])
        }
    }

    private func applyEQBand(index: Int, gain: Float) {
        guard eqHandle != 0 else { return }
        var params = BASS_BFX_PEAKEQ()
        params.lBand = Int32(index)
        params.fBandwidth = 1.0
        params.fQ = 0.707
        params.fCenter = Self.frequencies[index]
        params.fGain = gain
        params.lChannel = BASS_BFX_CHANALL
        BASS_FXSetParameters(eqHandle, &params)
    }

    private func removeEQFromStream() {
        if stream != 0, eqHandle != 0 {
            BASS_ChannelRemoveFX(stream, eqHandle)
        }
        eqHandle = 0
    }

    // MARK: - Transport

    private func applyVolume() {
        guard stream != 0 else { return }
        BASS_ChannelSetAttribute(stream, DWORD(BASS_ATTRIB_VOL), volume)
    }

    private func startPlayback(url: URL) {
        initializeBass()
        guard bassReady else {
            emitError("Не удалось инициализировать аудио")
            return
        }

        stopPlayback(emitIdle: false)
        wantsPlayback = true
        paused = false
        emitState(.loading)

        streamLock.lock()
        let request = requestCounter + 1
        requestCounter = request
        streamLock.unlock()

        let flags = DWORD(BASS_STREAM_BLOCK | BASS_STREAM_STATUS | BASS_SAMPLE_FLOAT)
        let newStream = url.absoluteString.withCString { pointer in
            BASS_StreamCreateURL(
                pointer,
                0,
                flags,
                nil,
                UnsafeMutableRawPointer(bitPattern: request)
            )
        }

        streamLock.lock()
        if request != requestCounter {
            streamLock.unlock()
            if newStream != 0 { BASS_StreamFree(newStream) }
            return
        }
        stream = newStream
        streamLock.unlock()

        guard stream != 0 else {
            emitError(bassErrorMessage(BASS_ErrorGetCode()))
            return
        }

        let user = Unmanaged.passUnretained(self).toOpaque()
        BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_META), 0, bassMetaSyncCallback, user)
        BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_OGG_CHANGE), 0, bassMetaSyncCallback, user)
        BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_STALL), 0, bassStallSyncCallback, user)
        BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_END), 0, bassEndSyncCallback, user)

        applyVolume()
        setupEQOnStream()
        emitICYTagsFromChannel()

        guard BASS_ChannelPlay(stream, 0) != 0 else {
            let code = BASS_ErrorGetCode()
            emitError(bassErrorMessage(code))
            freeStream()
            return
        }

        updateStateFromBass()
    }

    private func stopPlayback(emitIdle: Bool) {
        streamLock.lock()
        requestCounter += 1
        streamLock.unlock()

        // Cancels a connection that may still be blocked inside BASS_StreamCreateURL.
        _ = BASS_StreamCancel(UnsafeMutableRawPointer(bitPattern: requestCounter))
        freeStream()
        wantsPlayback = false
        paused = false
        if emitIdle { emitState(.idle) }
    }

    private func freeStream() {
        guard stream != 0 else { return }
        eqHandle = 0
        BASS_StreamFree(stream)
        stream = 0
    }

    private func updateStateFromBass() {
        guard stream != 0 else {
            emitState(wantsPlayback ? .loading : .idle)
            return
        }
        if paused {
            emitState(.paused)
            return
        }
        switch BASS_ChannelIsActive(stream) {
        case DWORD(BASS_ACTIVE_PLAYING): emitState(.playing)
        case DWORD(BASS_ACTIVE_PAUSED): emitState(.paused)
        case DWORD(BASS_ACTIVE_STALLED): emitState(.loading)
        default: emitState(wantsPlayback ? .loading : .idle)
        }
    }

    // MARK: - Metadata

    private func emitICYTagsFromChannel() {
        guard stream != 0 else { return }
        var tags = BASS_ChannelGetTags(stream, DWORD(BASS_TAG_ICY))
        if tags == nil {
            tags = BASS_ChannelGetTags(stream, DWORD(BASS_TAG_HTTP))
        }
        guard let tags else { return }
        parseTagList(tags)
    }

    private func parseTagList(_ tags: UnsafePointer<CChar>) {
        var pointer = tags
        while pointer.pointee != 0 {
            let line = String(cString: pointer)
            if line.lowercased().hasPrefix("icy-url:") {
                let url = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !url.isEmpty { emitICYURL(url) }
            }
            pointer = pointer.advanced(by: strlen(pointer) + 1)
        }
    }

    fileprivate func handleMetaSync() {
        guard stream != 0 else { return }
        if let meta = BASS_ChannelGetTags(stream, DWORD(BASS_TAG_META)),
           let title = parseShoutcastMeta(meta) {
            emitICY(title)
            return
        }
        if let ogg = BASS_ChannelGetTags(stream, DWORD(BASS_TAG_OGG)),
           let title = parseOggTags(ogg) {
            emitICY(title)
        }
    }

    fileprivate func handleStallSync(stalled: Bool) {
        emitState(stalled ? .loading : .playing)
    }

    fileprivate func handleEndSync() {
        streamLock.lock()
        stream = 0
        streamLock.unlock()
        wantsPlayback = false
        paused = false
        eqHandle = 0
        emitState(.idle)
    }

    private func parseShoutcastMeta(_ meta: UnsafePointer<CChar>) -> String? {
        let raw = String(cString: meta)
        guard let start = raw.range(of: "StreamTitle='") else { return nil }
        var title = String(raw[start.upperBound...])
        if let end = title.range(of: "';") {
            title = String(title[..<end.lowerBound])
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func parseOggTags(_ tags: UnsafePointer<CChar>) -> String? {
        var pointer = tags
        var artist: String?
        var title: String?
        while pointer.pointee != 0 {
            let entry = String(cString: pointer)
            let lower = entry.lowercased()
            if lower.hasPrefix("artist=") {
                artist = String(entry.dropFirst(7))
            } else if lower.hasPrefix("title=") {
                title = String(entry.dropFirst(6))
            }
            pointer = pointer.advanced(by: strlen(pointer) + 1)
        }
        if let title {
            if let artist, !artist.isEmpty {
                return "\(artist) — \(title)"
            }
            return title
        }
        return nil
    }

    private func bassErrorMessage(_ code: Int32) -> String {
        switch code {
        case BASS_ERROR_FILEFORM:
            return "Формат потока не поддерживается"
        case BASS_ERROR_TIMEOUT:
            return "Таймаут подключения к потоку"
        case BASS_ERROR_FILEOPEN:
            return "Не удалось открыть поток"
        default:
            return "Не удалось открыть поток (код \(code))"
        }
    }

    // MARK: - Events

    private func emitState(_ state: RadioPlaybackState) {
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(state)
        }
    }

    private func emitError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackError?(message)
        }
        emitState(.error)
    }

    private func emitICY(_ title: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onICYTitle?(title)
        }
    }

    private func emitICYURL(_ url: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onICYURL?(url)
        }
    }
}
