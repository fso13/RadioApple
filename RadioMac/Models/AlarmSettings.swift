import Foundation

/// Persisted schedule for the wake-up radio.
///
/// `weekdays` uses `Calendar.component(.weekday:)` values: 1 = Sunday …
/// 7 = Saturday. The UI displays them Monday-first.
struct AlarmSettings: Codable, Equatable {
    var enabled: Bool
    var hour: Int
    var minute: Int
    var weekdays: Set<Int>
    var stationID: String?
    var fadeInSeconds: Int

    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    static let initial = AlarmSettings(
        enabled: false,
        hour: 7,
        minute: 30,
        weekdays: [2, 3, 4, 5, 6],
        stationID: nil,
        fadeInSeconds: 30
    )

    init(
        enabled: Bool,
        hour: Int,
        minute: Int,
        weekdays: Set<Int>,
        stationID: String?,
        fadeInSeconds: Int
    ) {
        self.enabled = enabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.stationID = stationID
        self.fadeInSeconds = min(max(fadeInSeconds, 0), 120)
    }

    static func shortLabel(for weekday: Int) -> String {
        switch weekday {
        case 1: return "Вс"
        case 2: return "Пн"
        case 3: return "Вт"
        case 4: return "Ср"
        case 5: return "Чт"
        case 6: return "Пт"
        case 7: return "Сб"
        default: return "?"
        }
    }

    static func fullLabel(for weekday: Int) -> String {
        switch weekday {
        case 1: return "воскресенье"
        case 2: return "понедельник"
        case 3: return "вторник"
        case 4: return "среда"
        case 5: return "четверг"
        case 6: return "пятница"
        case 7: return "суббота"
        default: return "день"
        }
    }

    /// Next matching date strictly after `date`, or nil when disabled/no days.
    func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, !weekdays.isEmpty else { return nil }

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: day)
            guard weekdays.contains(weekday) else { continue }
            guard let candidate = calendar.date(
                bySettingHour: hour,
                minute: minute,
                second: 0,
                of: day
            ) else { continue }
            if candidate > date { return candidate }
        }
        return nil
    }
}
