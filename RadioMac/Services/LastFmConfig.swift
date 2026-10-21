import Foundation

/// Developer API keys injected at build time.
///
/// The values live in `LastFmAPIKey` / `LastFmAPISecret` in Info.plist and are
/// filled from the `LASTFM_API_KEY` / `LASTFM_API_SECRET` build settings. They
/// are never committed to the repository; the user only authorizes the account.
enum LastFmConfig {
    static var credentials: LastFmCredentials? {
        guard let key = value(for: "LastFmAPIKey"),
              let secret = value(for: "LastFmAPISecret")
        else { return nil }
        return LastFmCredentials(
            apiKey: key,
            apiSecret: secret,
            sessionKey: nil,
            username: nil
        )
    }

    static var hasDeveloperKeys: Bool { credentials != nil }

    private static func value(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}
