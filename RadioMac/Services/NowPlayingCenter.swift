import AppKit
import Foundation
import MediaPlayer

/// Publishes playback metadata to Control Center / the menu-bar Now Playing tile
/// and forwards the system transport commands back to the player.
final class NowPlayingCenter {
    static let shared = NowPlayingCenter()

    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onToggle: (() -> Void)?
    private var artworkTask: URLSessionDataTask?
    private var commandsConfigured = false
    private var artworkURL: String?

    func configure(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) {
        self.onPlay = onPlay
        self.onPause = onPause
        self.onToggle = onToggle

        guard !commandsConfigured else { return }
        commandsConfigured = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onToggle?()
            return .success
        }

        let disabled: [MPRemoteCommand] = [
            center.nextTrackCommand,
            center.previousTrackCommand,
            center.changePlaybackPositionCommand,
            center.seekForwardCommand,
            center.seekBackwardCommand,
            center.skipForwardCommand,
            center.skipBackwardCommand,
            center.ratingCommand,
            center.likeCommand,
            center.dislikeCommand,
        ]
        for command in disabled { command.isEnabled = false }
    }

    func update(
        title: String?,
        artist: String?,
        artworkURL: String?,
        isPlaying: Bool,
        isLive: Bool
    ) {
        var info: [String: Any] = [:]

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty { info[MPMediaItemPropertyTitle] = trimmedTitle }

        let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedArtist.isEmpty { info[MPMediaItemPropertyArtist] = trimmedArtist }

        info[MPNowPlayingInfoPropertyIsLiveStream] = isLive
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if isPlaying { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0 }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(from: artworkURL)
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(from urlString: String?) {
        let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty == false) ? trimmed : nil
        // Metadata updates arrive often (state changes, volume); only re-download
        // when the cover actually changed.
        guard normalized != artworkURL else { return }
        artworkURL = normalized

        artworkTask?.cancel()
        artworkTask = nil

        guard let raw = normalized, let url = URL(string: raw) else { return }

        artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            let size = image.size == .zero ? CGSize(width: 300, height: 300) : image.size
            let artwork = MPMediaItemArtwork(boundsSize: size) { _ in image }
            DispatchQueue.main.async {
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                updated[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                self.artworkTask = nil
            }
        }
        artworkTask?.resume()
    }
}
