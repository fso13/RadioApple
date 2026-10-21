import Combine
import Foundation

/// Opt-in local diagnostics: a small event journal plus crash detection via a
/// session marker. Nothing is uploaded; station URLs are reduced to their host.
final class DiagnosticsService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var lines: [String] = []
    @Published private(set) var lastCrashDate: Date?

    static let maxLines = 500

    private let defaults: UserDefaults
    private let store: DiagnosticsStore
    private let player: RadioPlayerService
    private var cancellables: Set<AnyCancellable> = []
    private var lastStationID: String?
    private var started = false

    init(
        defaults: UserDefaults = .standard,
        store: DiagnosticsStore? = nil,
        player: RadioPlayerService
    ) {
        self.defaults = defaults
        self.player = player
        self.store = store ?? DiagnosticsStore(directory: Self.defaultDirectory())
        isEnabled = defaults.boolLike(DefaultsKey.diagnosticsEnabled) ?? false
        observePlayer()
    }

    var logURL: URL { store.logURL }
    var hasLog: Bool { store.hasLog }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        guard isEnabled else { return }

        if let previous = store.beginSession(now: Date()) {
            lastCrashDate = previous
            append("crash", "предыдущий сеанс завершился аварийно: \(Self.timestamp(previous))")
        }
        append("app", "запуск RadioMac \(version), macOS \(Self.osVersion)")
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }

        if enabled {
            isEnabled = true
            defaults.set(true, forKey: DefaultsKey.diagnosticsEnabled)
            refresh()
            if let previous = store.beginSession(now: Date()) {
                lastCrashDate = previous
                append("crash", "предыдущий сеанс завершился аварийно: \(Self.timestamp(previous))")
            }
            append("app", "журнал включён")
        } else {
            if isEnabled {
                store.append(Self.line(
                    date: Date(),
                    category: "app",
                    message: "журнал выключен"
                ))
                store.endSession()
            }
            isEnabled = false
            defaults.set(false, forKey: DefaultsKey.diagnosticsEnabled)
            refresh()
        }
    }

    func markCleanExit() {
        guard isEnabled else { return }
        store.append(Self.line(date: Date(), category: "app", message: "завершение"))
        store.endSession()
    }

    func clear() {
        store.clear()
        lines = []
        if isEnabled {
            append("app", "журнал очищен")
        }
    }

    func refresh() {
        lines = Array(store.readLines().suffix(Self.maxLines))
    }

    func copyText() -> String {
        lines.joined(separator: "\n")
    }

    // MARK: - Entries

    private func append(_ category: String, _ message: String) {
        guard isEnabled else { return }
        let line = Self.line(date: Date(), category: category, message: message)
        store.append(line)
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    static func line(date: Date, category: String, message: String) -> String {
        "\(timestamp(date)) [\(category)] \(redact(message))"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Replaces full URLs with `scheme://host`, dropping paths, queries and
    /// fragments (which may contain stream tokens).
    static func redact(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false).map { part in
            let value = String(part)
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host
            else { return value }
            return "\(scheme)://\(host)"
        }
        .joined(separator: " ")
    }

    // MARK: - Player

    private func observePlayer() {
        player.$status
            .removeDuplicates()
            .sink { [weak self] status in
                self?.append("player", "status=\(status.rawValue)")
            }
            .store(in: &cancellables)

        player.$station
            .compactMap { $0 }
            .sink { [weak self] station in
                guard let self, station.id != self.lastStationID else { return }
                self.lastStationID = station.id
                let host = URL(string: station.url)?.host ?? "unknown"
                self.append("station", "\(station.name) (\(host))")
            }
            .store(in: &cancellables)

        player.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.append("error", message)
            }
            .store(in: &cancellables)
    }

    // MARK: - Environment

    private static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private var version: String {
        let short = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("RadioMac", isDirectory: true)
    }
}
