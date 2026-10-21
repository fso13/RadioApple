@preconcurrency import AVFoundation
import Foundation

/// AVPlayer-based engine for HLS and progressive streams.
///
/// This is the first stage of the native audio migration: playback, pause,
/// resume, volume and HLS timed metadata.
/// for MP3/AAC because it also provides ICY metadata and the equalizer.
@MainActor
final class NativeAudioEngine {
    var onStateChange: (@MainActor (RadioPlaybackState) -> Void)?
    var onMetadata: (@MainActor (String) -> Void)?
    var onPlaybackError: (@MainActor (String) -> Void)?

    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var endedObserver: NSObjectProtocol?

    private var wantsPlayback = false
    private var volume: Double = 0.8
    private var currentURL: URL?
    private let icyReader = ICYMetadataReader()
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var metadataDelegate: HLSMetadataDelegate?
    private var lastMetadata: String?
    private let equalizer = NativeEqualizer()
    private var audioMix: AVAudioMix?
    private var audioTap: MTAudioProcessingTap?

    func play(url: URL) {
        stopObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = Float(volume)
        player.automaticallyWaitsToMinimizeStalling = true

        self.item = item
        self.player = player
        currentURL = url
        wantsPlayback = true
        lastMetadata = nil
        audioMix = nil
        audioTap = nil

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let delegate = HLSMetadataDelegate()
        delegate.onTitle = { [weak self] raw in
            Task { @MainActor in self?.emitMetadata(raw) }
        }
        output.setDelegate(delegate, queue: .main)
        item.add(output)
        metadataOutput = output
        metadataDelegate = delegate

        icyReader.onTitle = { [weak self] raw in
            Task { @MainActor in self?.emitMetadata(raw) }
        }
        startICYIfNeeded()

        observe(item: item, player: player)
        onStateChange?(.loading)
        attachAudioMix(item: item, player: player)
    }

    func setEQEnabled(_ enabled: Bool) {
        equalizer.setEnabled(enabled)
    }

    func setEQGains(_ gains: [Double]) {
        equalizer.setGains(gains)
    }

    private func attachAudioMix(item: AVPlayerItem, player: AVPlayer) {
        Task { @MainActor [weak self] in
            guard let self, self.item === item, self.player === player else { return }

            if let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
               let result = AudioMixTapFactory.make(track: track, equalizer: self.equalizer) {
                guard self.item === item else { return }
                item.audioMix = result.mix
                self.audioMix = result.mix
                self.audioTap = result.tap
            }

            guard self.item === item, self.player === player else { return }
            player.play()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self,
                  self.item === item,
                  self.player === player,
                  player.timeControlStatus == .paused
            else { return }
            player.play()
        }
    }

    func pause() {
        wantsPlayback = false
        icyReader.stop()
        player?.pause()
        onStateChange?(.paused)
    }

    func resume() {
        guard player != nil else { return }
        wantsPlayback = true
        startICYIfNeeded()
        onStateChange?(.loading)
        player?.play()
    }

    func stop(emitIdle: Bool = true) {
        wantsPlayback = false
        icyReader.stop()
        currentURL = nil
        lastMetadata = nil
        audioMix = nil
        audioTap = nil
        stopObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        item = nil
        if emitIdle { onStateChange?(.idle) }
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        player?.volume = Float(volume)
    }

    private func startICYIfNeeded() {
        guard let currentURL,
              !currentURL.absoluteString.lowercased().contains(".m3u8")
        else {
            icyReader.stop()
            return
        }
        icyReader.start(url: currentURL)
    }

    /// AVPlayer does not expose stream properties synchronously.
    /// The diagnostics panel shows «—» for native streams until the AVAsset
    /// inspection lands in the next stage.
    func fetchStreamInfo(completion: @escaping @MainActor (StreamInfo?) -> Void) {
        guard let item, let player else {
            completion(nil)
            return
        }

        Task { @MainActor in
            var codec = Self.codecFallback(for: item.asset)
            var frequency = 0
            var channels = 0
            var estimatedBitrate: Double = 0

            if let track = item.tracks.first(where: { $0.assetTrack?.mediaType == .audio })?.assetTrack {
                if let formats = try? await track.load(.formatDescriptions),
                   let format = formats.first {
                    codec = StreamInfo.codecName(forSubType: CMFormatDescriptionGetMediaSubType(format))
                    if let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        frequency = Int(description.mSampleRate)
                        channels = Int(description.mChannelsPerFrame)
                    }
                }
                if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                    estimatedBitrate = Double(rate)
                }
            }

            let event = item.accessLog()?.events.last
            let observed = event?.observedBitrate ?? 0
            let indicated = event?.indicatedBitrate ?? 0
            let averageAudio = event?.averageAudioBitrate ?? 0
            var transfer = 0.0
            if let bytes = event?.numberOfBytesTransferred,
               let duration = event?.transferDuration,
               bytes > 0,
               duration > 0 {
                transfer = Double(bytes) * 8 / duration
            }
            let inferred = Self.inferredBitrate(
                from: (item.asset as? AVURLAsset)?.url
            )
            let bitrate = [observed, indicated, averageAudio, transfer, estimatedBitrate, inferred]
                .compactMap { $0 }
                .first(where: { $0 > 0 }) ?? 0

            let now = player.currentTime()
            let buffered = item.loadedTimeRanges
                .map { $0.timeRangeValue }
                .filter { $0.isValid && !$0.isEmpty }
                .map { CMTimeGetSeconds($0.end) - CMTimeGetSeconds(now) }
                .filter { $0.isFinite && $0 > 0 }
                .max() ?? 0

            let server = event?.serverAddress
                ?? URL(string: item.asset is AVURLAsset ? (item.asset as? AVURLAsset)?.url.absoluteString ?? "" : "")?.host

            completion(
                StreamInfo(
                    codec: codec,
                    frequency: frequency,
                    channels: channels,
                    bitrateKbps: bitrate > 0 ? Int((bitrate / 1_000).rounded()) : nil,
                    bufferMilliseconds: Int(buffered * 1_000),
                    server: server
                )
            )
        }
    }

    /// Some progressive streams advertise the bitrate only in the filename
    /// (for example `maximum96.aacp` or `nashe-128.mp3`).
    private static func inferredBitrate(from url: URL?) -> Double? {
        guard let url else { return nil }
        let name = url.lastPathComponent.lowercased()
        let pattern = #"([0-9]{2,3})(?:kbps|kbit)?\.(?:mp3|aac|aacp|m4a)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: name,
                range: NSRange(name.startIndex..., in: name)
              ),
              let range = Range(match.range(at: 1), in: name),
              let value = Double(name[range]),
              (32...512).contains(value)
        else { return nil }
        return value * 1_000
    }

    private static func codecFallback(for asset: AVAsset) -> String {
        guard let url = (asset as? AVURLAsset)?.url.absoluteString.lowercased() else {
            return "Audio"
        }
        if url.contains(".m3u8") { return "HLS/AAC" }
        if url.contains(".aac") { return "AAC" }
        if url.contains(".mp3") { return "MP3" }
        if url.contains(".m4a") { return "AAC" }
        return "Audio"
    }

    // MARK: - Observations

    private func observe(item: AVPlayerItem, player: AVPlayer) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) {
            [weak self] item, _ in
            let raw = item.status.rawValue
            let message = item.error?.localizedDescription
            Task { @MainActor in
                guard let status = AVPlayerItem.Status(rawValue: raw) else { return }
                self?.handleItemStatus(status, message: message)
            }
        }

        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            let raw = player.timeControlStatus.rawValue
            Task { @MainActor in
                guard let status = AVPlayer.TimeControlStatus(rawValue: raw) else { return }
                self?.handleTimeControl(status)
            }
        }

        let center = NotificationCenter.default
        failedObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "Поток прервался."
            Task { @MainActor in self?.handleFailure(message) }
        }

        endedObserver = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleEnded() }
        }
    }

    private func stopObservers() {
        if let metadataOutput {
            item?.remove(metadataOutput)
        }
        metadataOutput = nil
        metadataDelegate = nil
        itemStatusObservation?.invalidate()
        timeControlObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation = nil

        let center = NotificationCenter.default
        if let failedObserver {
            center.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        if let endedObserver {
            center.removeObserver(endedObserver)
            self.endedObserver = nil
        }
    }

    // MARK: - State

    private func handleItemStatus(_ status: AVPlayerItem.Status, message: String?) {
        switch status {
        case .readyToPlay:
            if wantsPlayback {
                player?.play()
            }
        case .failed:
            wantsPlayback = false
            icyReader.stop()
            onPlaybackError?(message ?? "Не удалось открыть поток.")
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleTimeControl(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            onStateChange?(.playing)
        case .waitingToPlayAtSpecifiedRate:
            if wantsPlayback { onStateChange?(.loading) }
        case .paused:
            if !wantsPlayback { onStateChange?(.paused) }
        @unknown default:
            break
        }
    }

    private func emitMetadata(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastMetadata else { return }
        lastMetadata = trimmed
        onMetadata?(trimmed)
    }

    private func handleFailure(_ message: String) {
        wantsPlayback = false
        icyReader.stop()
        onPlaybackError?(message)
    }

    private func handleEnded() {
        wantsPlayback = false
        icyReader.stop()
        onStateChange?(.idle)
    }
}
