import Foundation

/// Keys for `UserDefaults`.
enum DefaultsKey {
    static let stations = "stations_v1"
    static let volume = "volume"
    static let resumeLastStation = "resume_last_station"
    static let lastStationID = "last_station_id"
    static let autoStart = "auto_start"
    static let trackHistory = "track_history"
    static let globalHotKeyPlayPause = "global_hotkey_play_pause"
    static let globalHotKeyNext = "global_hotkey_next"
    static let themePreference = "theme_preference"
    static let eqEnabled = "eq_enabled"
    static let eqPreset = "eq_preset"
    static let eqGains = "eq_gains"
    static let eqCustomGains = "eq_custom_gains"
    static let alarmSettings = "alarm_settings"
    static let diagnosticsEnabled = "diagnostics_enabled"
    static let lastFmEnabled = "lastfm_enabled"
    static let musicAutoEnrich = "music_auto_enrich"
    static let musicSortOrder = "music_sort_order"
}

extension UserDefaults {
    /// Reads numbers that may have been persisted as strings by older builds.
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

    /// JSON array of station dictionaries.
    func stationsJSONString() -> String? {
        guard let raw = string(forKey: DefaultsKey.stations), !raw.isEmpty else { return nil }
        return raw
    }
}
