import Foundation

/// Backoff for unexpected stream failures: 1, 2, 5, 10 seconds.
struct ReconnectPolicy: Sendable, Equatable {
    let delays: [TimeInterval]

    init(delays: [TimeInterval] = [1, 2, 5, 10]) {
        self.delays = delays
    }

    var maxAttempts: Int { delays.count }

    func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt < delays.count else { return nil }
        return delays[attempt]
    }
}
