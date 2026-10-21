import Foundation

/// Transitional ICY metadata reader for the AVPlayer engine.
///
/// AVPlayer does not expose Shoutcast/Icecast `StreamTitle` metadata for
/// progressive streams, so this lightweight side-channel opens the stream with
/// `Icy-MetaData: 1`, discards the audio bytes and forwards only the metadata.
/// HLS does not use ICY; it will get a dedicated metadata output later.
final class ICYMetadataReader: @unchecked Sendable {
    var onTitle: (@Sendable (String) -> Void)?

    private var task: Task<Void, Never>?

    func start(url: URL) {
        stop()
        task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var request = URLRequest(url: url)
            request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
            request.setValue("RadioMac/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse,
                      let rawInterval = http.value(forHTTPHeaderField: "icy-metaint"),
                      let interval = Int(rawInterval),
                      interval > 0
                else { return }

                var audioBytes = 0
                var metadataRemaining = 0
                var metadata: [UInt8] = []

                for try await byte in bytes {
                    if Task.isCancelled { break }

                    if metadataRemaining > 0 {
                        metadata.append(byte)
                        metadataRemaining -= 1
                        if metadataRemaining == 0 {
                            if let title = Self.title(from: metadata) {
                                self.onTitle?(title)
                            }
                            metadata.removeAll(keepingCapacity: true)
                            audioBytes = 0
                        }
                        continue
                    }

                    if audioBytes == interval {
                        let length = Int(byte) * 16
                        audioBytes = 0
                        if length > 0 {
                            metadataRemaining = length
                        }
                    } else {
                        audioBytes += 1
                    }
                }
            } catch {
                // The side-channel is best-effort; playback does not depend on it.
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    static func title(from bytes: [UInt8]) -> String? {
        let raw = String(decoding: bytes, as: UTF8.self)
        return NowPlayingParser.unwrapICYBlock(raw)
    }
}
