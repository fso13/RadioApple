import Foundation
@preconcurrency import Sparkle

/// Sparkle 2 updater. The feed is a stable release asset URL, so the app does
/// not depend on the Pages deployment for updates.
@MainActor
final class UpdateService {
    static let shared = UpdateService()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [short, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
