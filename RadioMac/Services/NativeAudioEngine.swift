import AVFoundation
import Foundation

/// AVPlayer-based engine for HLS and progressive streams.
///
/// This is the first stage of the native audio migration: playback, pause,
/// resume, volume and HLS timed metadata. The BASS engine remains the default
/// for MP3/AAC because it also provides ICY metadata and the equalizer.
@MainActor
final class NativeAudioEngine {
    var onStateChange: (@MainActor (RadioPlaybackState) -> Void)?
    var onPlaybackError: (@MainActor (String) -> Void)?

    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var failedObserver: NSObjectProtocol?
    private var endedObserver: NSObjectProtocol?

    private var wantsPlayback = false
    private var volume: Double = 0.8

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
        wantsPlayback = true

        observe(item: item, player: player)
        onStateChange?(.loading)
        player.play()
    }

    func pause() {
        wantsPlayback = false
        player?.pause()
        onStateChange?(.paused)
    }

    func resume() {
        guard player != nil else { return }
        wantsPlayback = true
        onStateChange?(.loading)
        player?.play()
    }

    func stop() {
        wantsPlayback = false
        stopObservers()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        item = nil
        onStateChange?(.idle)
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        player?.volume = Float(volume)
    }

    /// AVPlayer does not expose BASS-style stream properties synchronously.
    /// The diagnostics panel shows «—» for native streams until the AVAsset
    /// inspection lands in the next stage.
    func fetchStreamInfo(completion: @escaping @MainActor (StreamInfo?) -> Void) {
        completion(nil)
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

    private func handleFailure(_ message: String) {
        wantsPlayback = false
        onPlaybackError?(message)
    }

    private func handleEnded() {
        wantsPlayback = false
        onStateChange?(.idle)
    }
}
