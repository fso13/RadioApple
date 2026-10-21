#if DEBUG
import Foundation

/// Debug builds append diagnostics to `<container tmp>/radio-debug.log`, which is
/// the only place a sandboxed menu-bar app can write without user consent.
enum DebugLog {
    private static let queue = DispatchQueue(label: "radio_mac.debuglog")
    private static let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("radio-debug.log")

    static var path: String { url.path }

    static func write(_ message: String) {
        queue.async {
            let line = "[\(Date().timeIntervalSince1970.rounded())] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
#endif
