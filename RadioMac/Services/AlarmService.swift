import AppKit
import Combine
import Foundation
import UserNotifications

/// Wake-up radio: a weekday schedule, station selection, fade-in and a local
/// notification. Works while RadioMac is running; after sleep it catches up if
/// the scheduled time passed within ten minutes.
@MainActor
final class AlarmService: ObservableObject {
    @Published private(set) var settings: AlarmSettings
    @Published private(set) var nextFireDate: Date?
    @Published private(set) var notificationDenied = false

    private let defaults: UserDefaults
    private let library: StationLibrary
    private let player: RadioPlayerService

    private var scheduleTimer: Timer?
    private var fadeTimer: Timer?
    private var fadeTarget: Double = 0
    private var fadeStarted = Date()
    private var lastTriggered: Date?
    private var activity: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []

    init(
        defaults: UserDefaults = .standard,
        library: StationLibrary,
        player: RadioPlayerService
    ) {
        self.defaults = defaults
        self.library = library
        self.player = player
        settings = Self.loadSettings(defaults) ?? .initial

        observePlayer()
        observeWake()
        schedule()
        updateActivity()
    }

    // MARK: - Public API

    func start() {
        schedule()
        updateActivity()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.enabled else { return }
        update { $0.enabled = enabled }
        if enabled {
            requestAuthorization()
        } else {
            cancelFade(restore: true)
        }
        schedule()
        updateActivity()
    }

    func setTime(hour: Int, minute: Int) {
        update {
            $0.hour = min(max(hour, 0), 23)
            $0.minute = min(max(minute, 0), 59)
        }
        schedule()
    }

    func toggleWeekday(_ weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        update {
            if $0.weekdays.contains(weekday) {
                $0.weekdays.remove(weekday)
            } else {
                $0.weekdays.insert(weekday)
            }
        }
        schedule()
    }

    func setStation(_ id: String?) {
        update { $0.stationID = id }
    }

    func setFadeInSeconds(_ seconds: Int) {
        update { $0.fadeInSeconds = min(max(seconds, 0), 120) }
    }

    // MARK: - Scheduling

    private func schedule() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil

        guard settings.enabled, let fireDate = settings.nextFireDate(after: Date()) else {
            nextFireDate = nil
            return
        }
        nextFireDate = fireDate

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    private func fire() {
        guard settings.enabled else {
            schedule()
            return
        }

        let now = Date()
        if let lastTriggered, now.timeIntervalSince(lastTriggered) < 60 { return }
        guard let station = resolveStation() else {
            schedule()
            return
        }

        lastTriggered = now
        player.play(station)
        startFade()
        postNotification(for: station)
        schedule()
    }

    private func resolveStation() -> RadioStation? {
        if let id = settings.stationID, let station = library.byID(id) {
            return station
        }
        return player.station ?? library.stations.first
    }

    private func handleWake() {
        guard settings.enabled else { return }

        let now = Date()
        if let next = nextFireDate,
           next <= now,
           now.timeIntervalSince(next) <= 600 {
            fire()
        } else {
            schedule()
        }
    }

    // MARK: - Fade-in

    static func fadeVolume(target: Double, elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return target }
        let progress = min(1, max(0, elapsed / duration))
        return target * progress
    }

    private func startFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        fadeTarget = player.volume
        fadeStarted = Date()

        guard settings.fadeInSeconds > 0, fadeTarget > 0 else { return }

        player.setVolume(0)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickFade() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func tickFade() {
        let elapsed = Date().timeIntervalSince(fadeStarted)
        let duration = TimeInterval(settings.fadeInSeconds)
        player.setVolume(
            Self.fadeVolume(target: fadeTarget, elapsed: elapsed, duration: duration)
        )
        if elapsed >= duration {
            player.setVolume(fadeTarget)
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    private func cancelFade(restore: Bool) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if restore, fadeTarget > 0 {
            player.setVolume(fadeTarget)
        }
    }

    // MARK: - Notifications

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            @Sendable [weak self] granted, error in
            let denied = !granted
            let message = error?.localizedDescription
            Task { @MainActor in
                self?.notificationDenied = denied
                if let message {
                    NSLog("RadioMac: alarm notification permission: %@", message)
                }
            }
        }
    }

    private func postNotification(for station: RadioStation) {
        let content = UNMutableNotificationContent()
        content.title = "RadioMac"
        content.body = "Будильник: \(station.name)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "alarm-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("RadioMac: alarm notification failed: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Persistence

    private static func loadSettings(_ defaults: UserDefaults) -> AlarmSettings? {
        guard let data = defaults.data(forKey: DefaultsKey.alarmSettings) else { return nil }
        return try? JSONDecoder().decode(AlarmSettings.self, from: data)
    }

    private func update(_ mutate: (inout AlarmSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: DefaultsKey.alarmSettings)
    }

    // MARK: - Observers

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
    }

    private func observePlayer() {
        player.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self, self.fadeTimer != nil else { return }
                if status == .idle || status == .error || status == .paused {
                    self.cancelFade(restore: true)
                }
            }
            .store(in: &cancellables)
    }

    private func updateActivity() {
        if settings.enabled {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "RadioMac alarm"
            )
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
