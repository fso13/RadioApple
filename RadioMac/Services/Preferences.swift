import Foundation

/// Keys for `UserDefaults`. They intentionally match the Flutter build so that
/// preferences can be imported once (`flutter.` prefix) and stay readable.
enum DefaultsKey {
    static let stations = "stations_v1"
    static let volume = "volume"
    static let resumeLastStation = "resume_last_station"
    static let lastStationID = "last_station_id"
    static let autoStart = "auto_start"
    static let themePreference = "theme_preference"
    static let eqEnabled = "eq_enabled"
    static let eqPreset = "eq_preset"
    static let eqGains = "eq_gains"
    static let eqCustomGains = "eq_custom_gains"
    static let alarmSettings = "alarm_settings"
    static let diagnosticsEnabled = "diagnostics_enabled"
    static let migrationFlag = "native_migration_v1"

    /// `shared_preferences` on macOS stores every entry with this prefix.
    static let flutterPrefix = "flutter."
}

extension UserDefaults {
    /// Reads numbers that may have been persisted as strings by `shared_preferences`.
    func doubleLike(_ key: String) -> Double? {
        switch object(forKey: key) {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    func intLike(_ key: String) -> Int? {
        switch object(forKey: key) {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    func boolLike(_ key: String) -> Bool? {
        switch object(forKey: key) {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    /// JSON array of station dictionaries, stored either natively or by Flutter.
    func stationsJSONString() -> String? {
        if let raw = string(forKey: DefaultsKey.stations), !raw.isEmpty { return raw }
        if let raw = string(forKey: DefaultsKey.flutterPrefix + DefaultsKey.stations), !raw.isEmpty {
            return raw
        }
        return nil
    }
}

/// One-shot import of the settings written by the previous Flutter version of
/// the app (they live in the same sandbox container, keyed with `flutter.`).
enum PreferencesMigrator {
    static func migrateIfNeeded(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: DefaultsKey.migrationFlag) else { return }

        let keys = [
            DefaultsKey.volume,
            DefaultsKey.resumeLastStation,
            DefaultsKey.lastStationID,
            DefaultsKey.autoStart,
            DefaultsKey.themePreference,
            DefaultsKey.eqEnabled,
            DefaultsKey.eqPreset,
            DefaultsKey.eqGains,
            DefaultsKey.eqCustomGains,
        ]

        for key in keys {
            let source = DefaultsKey.flutterPrefix + key
            guard defaults.object(forKey: key) == nil,
                  let value = defaults.object(forKey: source)
            else { continue }
            defaults.set(value, forKey: key)
        }

        if let raw = defaults.string(forKey: DefaultsKey.flutterPrefix + DefaultsKey.stations),
           defaults.object(forKey: DefaultsKey.stations) == nil,
           !raw.isEmpty {
            defaults.set(raw, forKey: DefaultsKey.stations)
        }

        defaults.set(true, forKey: DefaultsKey.migrationFlag)
    }
}
