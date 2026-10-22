import Combine
import Foundation

/// Session sleep timer with a five-second fade-out.
@MainActor
final class SleepTimerService: ObservableObject {
    enum Option: Int, CaseIterable, Identifiable, Sendable {
        case fifteen = 15
        case thirty = 30
        case sixty = 60
        case ninety = 90

        var id: Int { rawValue }
        var title: String { "\(rawValue) минут" }
    }

    @Published private(set) var endsAt: Date?
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isFading = false

    private weak var player: RadioPlayerService?
    private var ticker: Timer?
    private var fadeTask: Task<Void, Never>?

    init(player: RadioPlayerService) {
        self.player = player
    }

    var isActive: Bool { endsAt != nil }

    var remainingText: String {
        guard isActive else { return "" }
        return Self.format(remaining)
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func start(minutes: Int) {
        cancel()
        let duration = TimeInterval(max(1, minutes) * 60)
        endsAt = Date().addingTimeInterval(duration)
        remaining = duration
        isFading = false
        player?.setFadeFactor(1)

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        fadeTask?.cancel()
        fadeTask = nil
        endsAt = nil
        remaining = 0
        isFading = false
        player?.setFadeFactor(1)
    }

    private func tick() {
        guard let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSinceNow)
        if remaining <= 5, !isFading {
            beginFade()
        }
        if remaining <= 0 {
            finish()
        }
    }

    private func beginFade() {
        isFading = true
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self] in
            let steps = 50
            for step in 0...steps {
                guard let self, !Task.isCancelled else { return }
                self.player?.setFadeFactor(1 - Double(step) / Double(steps))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        fadeTask?.cancel()
        fadeTask = nil
        endsAt = nil
        remaining = 0
        isFading = false
        player?.pause()
        player?.setFadeFactor(1)
    }
}
