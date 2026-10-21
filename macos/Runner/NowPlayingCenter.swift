import AppKit
import Foundation
import MediaPlayer

/// Publishes playback metadata to the macOS Control Center / menu bar Now Playing tray.
final class NowPlayingCenter {
  static let shared = NowPlayingCenter()

  private weak var engine: RadioEngine?
  private var artworkTask: URLSessionDataTask?
  private var commandsConfigured = false

  func configure(with engine: RadioEngine) {
    self.engine = engine
    guard !commandsConfigured else { return }
    commandsConfigured = true

    let center = MPRemoteCommandCenter.shared()
    center.playCommand.isEnabled = true
    center.playCommand.addTarget { [weak self] _ in
      self?.engine?.remotePlay()
      return .success
    }
    center.pauseCommand.isEnabled = true
    center.pauseCommand.addTarget { [weak self] _ in
      self?.engine?.remotePause()
      return .success
    }
    center.togglePlayPauseCommand.isEnabled = true
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.engine?.remoteTogglePlayPause()
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
    for command in disabled {
      command.isEnabled = false
    }
  }

  func update(
    title: String?,
    artist: String?,
    artworkUrl: String?,
    isPlaying: Bool,
    isLive: Bool
  ) {
    var info: [String: Any] = [:]

    let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmedTitle.isEmpty {
      info[MPMediaItemPropertyTitle] = trimmedTitle
    }

    let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmedArtist.isEmpty {
      info[MPMediaItemPropertyArtist] = trimmedArtist
    }

    info[MPNowPlayingInfoPropertyIsLiveStream] = isLive
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    if isPlaying {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    loadArtwork(from: artworkUrl)
  }

  func clear() {
    artworkTask?.cancel()
    artworkTask = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func loadArtwork(from urlString: String?) {
    artworkTask?.cancel()
    artworkTask = nil

    guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
          !urlString.isEmpty,
          let url = URL(string: urlString)
    else { return }

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
