import Combine
import Foundation

/// Small persisted preferences: volume, resume-on-launch, last station, autostart.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published private(set) var volume: Double
    @Published private(set) var resumeLastStation: Bool
    @Published private(set) var lastStationID: String?
    @Published private(set) var autoStartEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        volume = min(1, max(0, defaults.doubleLike(DefaultsKey.volume) ?? 0.8))
        resumeLastStation = defaults.boolLike(DefaultsKey.resumeLastStation) ?? false
        lastStationID = defaults.string(forKey: DefaultsKey.lastStationID)
        autoStartEnabled = defaults.boolLike(DefaultsKey.autoStart) ?? false
    }

    func setVolume(_ value: Double) {
        let clamped = min(1, max(0, value))
        guard clamped != volume else { return }
        volume = clamped
        defaults.set(clamped, forKey: DefaultsKey.volume)
    }

    func setResumeLastStation(_ value: Bool) {
        guard value != resumeLastStation else { return }
        resumeLastStation = value
        defaults.set(value, forKey: DefaultsKey.resumeLastStation)
    }

    func setLastStationID(_ id: String?) {
        lastStationID = id
        if let id {
            defaults.set(id, forKey: DefaultsKey.lastStationID)
        } else {
            defaults.removeObject(forKey: DefaultsKey.lastStationID)
        }
    }

    func setAutoStartEnabled(_ value: Bool) {
        guard value != autoStartEnabled else { return }
        autoStartEnabled = value
        defaults.set(value, forKey: DefaultsKey.autoStart)
    }
}
