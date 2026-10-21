import Foundation

/// Engine-neutral playback state reported by the native audio engine.
enum RadioPlaybackState: String, Sendable {
    case idle
    case loading
    case playing
    case paused
    case reconnecting
    case error
}
