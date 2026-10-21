import Foundation

/// File storage for the opt-in diagnostics journal. Kept separate from the
/// service so writing, trimming and crash-marker handling can be unit-tested.
final class DiagnosticsStore: @unchecked Sendable {
    let directory: URL
    let logURL: URL
    let markerURL: URL

    private let limitBytes: Int
    private let lock = NSLock()

    init(directory: URL, limitBytes: Int = 200_000) {
        self.directory = directory
        self.limitBytes = limitBytes
        logURL = directory.appendingPathComponent("diagnostics.log")
        markerURL = directory.appendingPathComponent("session.active")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var hasLog: Bool {
        FileManager.default.fileExists(atPath: logURL.path)
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }

        ensureDirectory()
        guard let data = (line + "\n").data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
        trimIfNeeded()
    }

    func readLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: logURL)
    }

    /// Writes a new session marker and returns the previous marker date, if the
    /// last session did not finish cleanly.
    func beginSession(now: Date) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        ensureDirectory()
        var previous: Date?
        if let data = try? Data(contentsOf: markerURL),
           let text = String(data: data, encoding: .utf8),
           let date = ISO8601DateFormatter().date(
               from: text.trimmingCharacters(in: .whitespacesAndNewlines)
           ) {
            previous = date
        }

        let stamp = ISO8601DateFormatter().string(from: now)
        try? stamp.data(using: .utf8)?.write(to: markerURL, options: .atomic)
        return previous
    }

    func endSession() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: markerURL)
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func trimIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size > limitBytes,
              let data = try? Data(contentsOf: logURL)
        else { return }

        let suffix = data.suffix(limitBytes / 2)
        let text = String(decoding: suffix, as: UTF8.self)
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
        try? lines.joined(separator: "\n").data(using: .utf8)?
            .write(to: logURL, options: .atomic)
    }
}
