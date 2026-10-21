import Foundation

enum RadioIntentError: LocalizedError {
    case notReady
    case unknownStation(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "RadioMac ещё не готова. Попробуйте ещё раз."
        case .unknownStation(let id):
            return "Станция «\(id)» не найдена в библиотеке."
        }
    }
}

/// Shared bridge between App Intents / URL commands and the running UI.
@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    private(set) var environment: AppEnvironment?
    private var showWindowAction: (() -> Void)?
    private var showSettingsAction: (() -> Void)?
    private var pendingCommands: [RadioURLCommand] = []

    func install(
        environment: AppEnvironment,
        showWindow: @escaping () -> Void,
        showSettings: @escaping () -> Void
    ) {
        self.environment = environment
        showWindowAction = showWindow
        showSettingsAction = showSettings
        let commands = pendingCommands
        pendingCommands = []
        commands.forEach(handle)
    }

    func handle(_ command: RadioURLCommand) {
        guard environment != nil else {
            pendingCommands.append(command)
            return
        }
#if DEBUG
        DebugLog.write("runtime command: \(String(describing: command))")
#endif
        switch command {
        case .play(let id):
            if let environment, let station = environment.library.byID(id) {
                environment.player.play(station)
            }
        case .pause:
            environment?.player.pause()
        case .toggle:
            environment?.player.togglePlayPause()
        case .open:
            showWindowAction?()
        }
    }

    var stations: [RadioStation] {
        environment?.library.stations ?? []
    }

    func waitUntilReady() async throws -> AppEnvironment {
        for _ in 0..<100 {
            if let environment { return environment }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        throw RadioIntentError.notReady
    }

    func playStation(id: String) async throws {
        let environment = try await waitUntilReady()
        guard let station = environment.library.byID(id) else {
            throw RadioIntentError.unknownStation(id)
        }
        environment.player.play(station)
    }

    func pause() async throws {
        let environment = try await waitUntilReady()
        environment.player.pause()
    }

    func openWindow() async throws {
        _ = try await waitUntilReady()
        showWindowAction?()
    }

    func openSettings() async throws {
        _ = try await waitUntilReady()
        showSettingsAction?()
    }
}
