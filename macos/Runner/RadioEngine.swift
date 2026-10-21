import FlutterMacOS
import Foundation

private func bassMetaSyncCallback(
  _ handle: HSYNC,
  _ channel: DWORD,
  _ data: DWORD,
  _ user: UnsafeMutableRawPointer?
) {
  guard let user else { return }
  let engine = Unmanaged<RadioEngine>.fromOpaque(user).takeUnretainedValue()
  engine.workQueue.async {
    engine.handleMetaSync()
  }
}

private func bassStallSyncCallback(
  _ handle: HSYNC,
  _ channel: DWORD,
  _ data: DWORD,
  _ user: UnsafeMutableRawPointer?
) {
  guard let user else { return }
  let engine = Unmanaged<RadioEngine>.fromOpaque(user).takeUnretainedValue()
  engine.workQueue.async {
    engine.handleStallSync(stalled: data == 0)
  }
}

private func bassEndSyncCallback(
  _ handle: HSYNC,
  _ channel: DWORD,
  _ data: DWORD,
  _ user: UnsafeMutableRawPointer?
) {
  guard let user else { return }
  let engine = Unmanaged<RadioEngine>.fromOpaque(user).takeUnretainedValue()
  engine.workQueue.async {
    engine.handleEndSync()
  }
}

private func bassStatusCallback(
  _ buffer: UnsafeRawPointer?,
  _ length: DWORD,
  _ user: UnsafeMutableRawPointer?
) {
  guard let user else { return }
  let request = Int(bitPattern: user)
  let engine = RadioEngine.shared
  engine.streamLock.lock()
  let current = engine.requestCounter
  engine.streamLock.unlock()
  if request != current { return }
  if buffer == nil && length == 0 {
    // HTTP status line during connect — ignored.
  }
}

/// Internet radio playback via the BASS library (un4seen).
final class RadioEngine: NSObject, FlutterStreamHandler {
  static let shared = RadioEngine()

  private var eventSink: FlutterEventSink?
  private var lastStatePayload: [String: Any]?

  fileprivate let workQueue = DispatchQueue(label: "radio_mac.bass")
  fileprivate let streamLock = NSLock()

  private var stream: HSTREAM = 0
  fileprivate var requestCounter: Int = 0
  private var wantsPlayback = false
  private var paused = false
  private var volume: Float = 0.8
  private var bassReady = false
  private var pluginsLoaded = false
  private var fxAvailable = false
  private var eqFxHandle: HFX = 0

  private let eqLock = NSLock()
  private var eqEnabled = false
  private var gains: [Float] = Array(repeating: 0, count: 10)

  private static let frequencies: [Float] = [
    32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000,
  ]

  override init() {
    super.init()
    initializeBass()
  }

  deinit {
    workQueue.sync {
      freeStream()
      if bassReady {
        BASS_Free()
        bassReady = false
      }
    }
  }

  func setup(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: "radio_mac/player", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    let events = FlutterEventChannel(
      name: "radio_mac/player_events",
      binaryMessenger: messenger
    )
    events.setStreamHandler(self)
    NowPlayingCenter.shared.configure(with: self)
  }

  func remotePlay() {
    resume()
  }

  func remotePause() {
    pause()
  }

  func remoteTogglePlayPause() {
    workQueue.async { [weak self] in
      guard let self else { return }
      if self.paused {
        self.resume()
      } else if self.stream != 0 {
        self.pause()
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    if let lastStatePayload {
      events(lastStatePayload)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "play":
      guard let urlString = call.arguments as? String, let url = URL(string: urlString) else {
        result(FlutterError(code: "bad_url", message: "Invalid stream URL", details: nil))
        return
      }
      play(url: url)
      result(nil)
    case "pause":
      pause()
      result(nil)
    case "resume":
      resume()
      result(nil)
    case "stop":
      stop()
      result(nil)
    case "setVolume":
      if let value = call.arguments as? Double {
        setVolume(Float(value))
      }
      result(nil)
    case "setEqEnabled":
      if let value = call.arguments as? Bool {
        eqLock.lock()
        eqEnabled = value
        eqLock.unlock()
        applyEqSettings()
      }
      result(nil)
    case "setEqGains":
      if let values = call.arguments as? [Double] {
        eqLock.lock()
        for i in 0..<min(gains.count, values.count) {
          gains[i] = max(-12, min(12, Float(values[i])))
        }
        eqLock.unlock()
        applyEqSettings()
      }
      result(nil)
    case "getState":
      result(currentStateValue())
    case "updateNowPlaying":
      if let args = call.arguments as? [String: Any] {
        NowPlayingCenter.shared.update(
          title: args["title"] as? String,
          artist: args["artist"] as? String,
          artworkUrl: args["artworkUrl"] as? String,
          isPlaying: args["isPlaying"] as? Bool ?? false,
          isLive: args["isLive"] as? Bool ?? true
        )
        result(nil)
      } else {
        result(FlutterError(code: "bad_args", message: "Invalid now playing args", details: nil))
      }
    case "clearNowPlaying":
      NowPlayingCenter.shared.clear()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initializeBass() {
    if bassReady { return }
    let version = BASS_GetVersion()
    let apiVersion = (version >> 16) & 0xffff
    if apiVersion != BASSVERSION {
      NSLog("RadioMac: incorrect BASS library version")
      return
    }
    if BASS_Init(-1, 44_100, 0, nil, nil) == 0 {
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
    guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent(name) else {
      return nil
    }
    return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
  }

  private func loadPlugins() {
    guard !pluginsLoaded else { return }
    if let path = pluginPath("libbass_aac.dylib") {
      if BASS_PluginLoad(path, 0) != 0 {
        NSLog("RadioMac: BASS_AAC loaded")
      } else {
        NSLog("RadioMac: BASS_AAC unavailable (%d), system AAC may still work", BASS_ErrorGetCode())
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

  private func applyEqSettings() {
    workQueue.async { [weak self] in
      self?.setupEqOnStream()
    }
  }

  private func setupEqOnStream() {
    guard stream != 0 else { return }
    removeEqFromStream()

    eqLock.lock()
    let enabled = eqEnabled
    let currentGains = gains
    eqLock.unlock()

    guard enabled, fxAvailable else { return }

    eqFxHandle = BASS_ChannelSetFX(stream, DWORD(BASS_FX_BFX_PEAKEQ), 0)
    if eqFxHandle == 0 {
      NSLog("RadioMac: EQ FX failed (%d)", BASS_ErrorGetCode())
      return
    }

    for index in 0..<min(currentGains.count, RadioEngine.frequencies.count) {
      applyEqBand(index: index, gain: currentGains[index])
    }
  }

  private func applyEqBand(index: Int, gain: Float) {
    guard eqFxHandle != 0 else { return }
    var params = BASS_BFX_PEAKEQ()
    params.lBand = Int32(index)
    params.fBandwidth = 1.0
    params.fQ = 0.707
    params.fCenter = RadioEngine.frequencies[index]
    params.fGain = gain
    params.lChannel = BASS_BFX_CHANALL
    BASS_FXSetParameters(eqFxHandle, &params)
  }

  private func removeEqFromStream() {
    if stream != 0 && eqFxHandle != 0 {
      BASS_ChannelRemoveFX(stream, eqFxHandle)
    }
    eqFxHandle = 0
  }

  private func play(url: URL) {
    workQueue.async { [weak self] in
      self?.startPlayback(url: url)
    }
  }

  private func pause() {
    workQueue.async { [weak self] in
      guard let self, self.stream != 0 else { return }
      if BASS_ChannelPause(self.stream) != 0 {
        self.paused = true
        self.emitState("paused")
      }
    }
  }

  private func resume() {
    workQueue.async { [weak self] in
      guard let self, self.stream != 0 else { return }
      if BASS_ChannelPlay(self.stream, 0) != 0 {
        self.paused = false
        self.wantsPlayback = true
        self.emitState("playing")
      }
    }
  }

  private func stop() {
    workQueue.async { [weak self] in
      self?.stopPlayback(emitIdle: true)
    }
  }

  private func setVolume(_ value: Float) {
    volume = max(0, min(1, value))
    workQueue.async { [weak self] in
      self?.applyVolume()
    }
  }

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
    emitState("loading")

    streamLock.lock()
    let request = requestCounter + 1
    requestCounter = request
    streamLock.unlock()

    let flags = DWORD(BASS_STREAM_BLOCK | BASS_STREAM_STATUS | BASS_SAMPLE_FLOAT)
    let urlString = url.absoluteString
    let newStream = BASS_StreamCreateURL(
      urlString,
      0,
      flags,
      bassStatusCallback,
      UnsafeMutableRawPointer(bitPattern: request)
    )

    streamLock.lock()
    if request != requestCounter {
      streamLock.unlock()
      if newStream != 0 {
        BASS_StreamFree(newStream)
      }
      return
    }
    stream = newStream
    streamLock.unlock()

    if stream == 0 {
      let code = BASS_ErrorGetCode()
      emitError(bassErrorMessage(code))
      return
    }

    // Status callback only needed for HTTP tags during connect.
    var nilProc: UnsafeMutableRawPointer? = nil
    BASS_ChannelSetAttributeEx(
      stream,
      DWORD(BASS_ATTRIB_DOWNLOADPROC),
      &nilProc,
      DWORD(MemoryLayout<UnsafeMutableRawPointer?>.size)
    )

    let user = Unmanaged.passUnretained(self).toOpaque()
    BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_META), 0, bassMetaSyncCallback, user)
    BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_OGG_CHANGE), 0, bassMetaSyncCallback, user)
    BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_STALL), 0, bassStallSyncCallback, user)
    BASS_ChannelSetSync(stream, DWORD(BASS_SYNC_END), 0, bassEndSyncCallback, user)

    applyVolume()
    setupEqOnStream()
    emitIcyTagsFromChannel()

    if BASS_ChannelPlay(stream, 0) == 0 {
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
    BASS_StreamCancel(UnsafeMutableRawPointer(bitPattern: requestCounter))
    freeStream()
    wantsPlayback = false
    paused = false
    if emitIdle {
      emitState("idle")
    }
  }

  private func freeStream() {
    if stream != 0 {
      eqFxHandle = 0
      BASS_StreamFree(stream)
      stream = 0
    }
  }

  private func updateStateFromBass() {
    guard stream != 0 else {
      emitState(wantsPlayback ? "loading" : "idle")
      return
    }
    if paused {
      emitState("paused")
      return
    }
    switch BASS_ChannelIsActive(stream) {
    case DWORD(BASS_ACTIVE_PLAYING):
      emitState("playing")
    case DWORD(BASS_ACTIVE_PAUSED):
      emitState("paused")
    case DWORD(BASS_ACTIVE_STALLED):
      emitState("loading")
    default:
      emitState(wantsPlayback ? "loading" : "idle")
    }
  }

  private func currentStateValue() -> String {
    guard stream != 0 else { return wantsPlayback ? "loading" : "idle" }
    if paused { return "paused" }
    switch BASS_ChannelIsActive(stream) {
    case DWORD(BASS_ACTIVE_PLAYING): return "playing"
    case DWORD(BASS_ACTIVE_PAUSED): return "paused"
    case DWORD(BASS_ACTIVE_STALLED): return "loading"
    default: return wantsPlayback ? "loading" : "idle"
    }
  }

  private func emitIcyTagsFromChannel() {
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
      let lower = line.lowercased()
      if lower.hasPrefix("icy-url:") {
        let url = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty {
          emit(["type": "icy_url", "url": url])
        }
      }
      pointer = UnsafePointer(pointer.advanced(by: line.utf8.count + 1))
    }
  }

  fileprivate func handleMetaSync() {
    guard stream != 0 else { return }
    if let meta = BASS_ChannelGetTags(stream, DWORD(BASS_TAG_META)) {
      if let title = parseShoutcastMeta(meta) {
        emit(["type": "icy", "title": title])
        return
      }
    }
    if let ogg = BASS_ChannelGetTags(stream, DWORD(BASS_TAG_OGG)) {
      if let title = parseOggTags(ogg) {
        emit(["type": "icy", "title": title])
      }
    }
  }

  fileprivate func handleStallSync(stalled: Bool) {
    if stalled {
      emitState("loading")
    } else {
      emitState("playing")
    }
  }

  fileprivate func handleEndSync() {
    streamLock.lock()
    stream = 0
    streamLock.unlock()
    wantsPlayback = false
    paused = false
    emitState("idle")
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
      pointer = UnsafePointer(pointer.advanced(by: entry.utf8.count + 1))
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

  private func emitError(_ message: String) {
    emit(["type": "error", "message": message])
    emitState("error")
  }

  private func emitState(_ value: String) {
    emit(["type": "state", "value": value])
  }

  private func emit(_ payload: [String: Any]) {
    if payload["type"] as? String == "state" {
      lastStatePayload = payload
    }
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }
}
