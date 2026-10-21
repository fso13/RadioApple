import AVFoundation
import Foundation

/// Receives HLS timed metadata from `AVPlayerItemMetadataOutput`.
///
/// The output is the non-deprecated replacement for `AVPlayerItem.timedMetadata`.
/// Its delegate callback runs on the queue configured by `NativeAudioEngine`
/// (the main queue); only the extracted string crosses to the engine.
final class HLSMetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate, @unchecked Sendable {
    var onTitle: (@Sendable (String) -> Void)?

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        var artist: String?
        var title: String?

        for group in groups {
            for item in group.items {
                // `AVMetadataItem.value` was deprecated in favour of async
                // `load(.value)`; the delegate callback is synchronous and
                // runs on the main queue, so read the same property via KVC.
                guard let raw = item.value(forKey: "value") as? String else { continue }
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }

                switch item.commonKey?.rawValue {
                case "artist":
                    artist = value
                case "title":
                    title = value
                default:
                    let identifier = item.identifier?.rawValue.lowercased() ?? ""
                    if identifier.contains("artist") {
                        artist = value
                    } else if identifier.contains("title") {
                        title = value
                    }
                }
            }
        }

        if let artist, let title {
            onTitle?("\(artist) - \(title)")
        } else if let title {
            onTitle?(title)
        }
    }
}
