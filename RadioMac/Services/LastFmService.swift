import AppKit
import Combine
import Foundation

/// Opt-in Last.fm scrobbling. API keys are supplied by the user and kept in
/// the Keychain; nothing is sent until the feature is enabled and connected.
@MainActor
final class LastFmService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var credentials: LastFmCredentials?
    @Published private(set) var isConnected: Bool
    @Published private(set) var username: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    @Published private(set) var isAuthorizing = false
    @Published private(set) var pendingToken: String?
    @Published private(set) var pendingAuthURL: URL?

    static let scrobbleThreshold: TimeInterval = 240

    private struct Track: Equatable, Sendable {
        let artist: String
        let title: String
        let album: String?
        let key: String
    }

    private let defaults: UserDefaults
    private let player: RadioPlayerService
    private var client: LastFmClient?
    private var activeTrack: Track?
    private var activeStartedAt: Date?
    private var lastNowPlayingKey: String?
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard, player: RadioPlayerService) {
        self.defaults = defaults
        self.player = player

        let stored = LastFmCredentialStore.load()
        credentials = stored
        isConnected = stored?.sessionKey != nil
        username = stored?.username
        isEnabled = defaults.boolLike(DefaultsKey.lastFmEnabled) ?? false
        client = stored.map { LastFmClient(apiKey: $0.apiKey, apiSecret: $0.apiSecret) }
        observePlayer()
    }

    static func shouldScrobble(elapsed: TimeInterval) -> Bool {
        elapsed >= scrobbleThreshold
    }

    // MARK: - Opt-in

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.lastFmEnabled)

        if enabled {
            statusMessage = isConnected ? "Скробблинг включён." : "Подключите Last.fm."
            handleNowPlaying()
        } else {
            finalizeTrack()
            statusMessage = "Скробблинг выключен."
        }
    }

    func saveCredentials(apiKey: String, apiSecret: String) -> Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !secret.isEmpty else {
            lastError = "Заполните API key и API secret."
            return false
        }

        let next = LastFmCredentials(
            apiKey: key,
            apiSecret: secret,
            sessionKey: nil,
            username: nil
        )
        do {
            try LastFmCredentialStore.save(next)
        } catch {
            lastError = error.localizedDescription
            return false
        }

        credentials = next
        client = LastFmClient(apiKey: key, apiSecret: secret)
        isConnected = false
        username = nil
        pendingToken = nil
        pendingAuthURL = nil
        statusMessage = "Ключи сохранены. Авторизуйте Last.fm."
        lastError = nil
        return true
    }

    // MARK: - OAuth

    func startAuthorization() {
        guard let client, credentials != nil else {
            lastError = "Сначала сохраните API-ключи."
            return
        }
        guard !isAuthorizing else { return }

        isAuthorizing = true
        lastError = nil
        statusMessage = "Получаем токен Last.fm…"

        Task {
            do {
                let token = try await client.requestToken()
                pendingToken = token
                let url = try client.authURL(token: token)
                pendingAuthURL = url
                statusMessage = "Авторизуйте RadioMac на Last.fm и нажмите «Готово»."
                NSWorkspace.shared.open(url)
            } catch {
                lastError = error.localizedDescription
                statusMessage = nil
            }
            isAuthorizing = false
        }
    }

    func completeAuthorization() {
        guard !isAuthorizing,
              let token = pendingToken,
              let client,
              var next = credentials
        else {
            lastError = "Нет ожидающей авторизации."
            return
        }

        isAuthorizing = true
        lastError = nil
        statusMessage = "Завершаем авторизацию…"

        Task {
            do {
                let session = try await client.session(token: token)
                next.sessionKey = session.key
                next.username = session.username
                try LastFmCredentialStore.save(next)

                credentials = next
                username = session.username
                isConnected = true
                pendingToken = nil
                pendingAuthURL = nil
                statusMessage = "Подключено: \(session.username)"
                lastError = nil

                if !isEnabled {
                    isEnabled = true
                    defaults.set(true, forKey: DefaultsKey.lastFmEnabled)
                }
                handleNowPlaying()
            } catch {
                lastError = error.localizedDescription
                statusMessage = nil
            }
            isAuthorizing = false
        }
    }

    func disconnect() {
        finalizeTrack()
        isEnabled = false
        defaults.set(false, forKey: DefaultsKey.lastFmEnabled)

        guard var next = credentials else { return }
        next.sessionKey = nil
        next.username = nil
        try? LastFmCredentialStore.save(next)

        credentials = next
        isConnected = false
        username = nil
        pendingToken = nil
        pendingAuthURL = nil
        statusMessage = "Last.fm отключён."
        lastError = nil
    }

    func forgetCredentials() {
        finalizeTrack()
        LastFmCredentialStore.clear()
        credentials = nil
        client = nil
        isConnected = false
        username = nil
        isEnabled = false
        defaults.set(false, forKey: DefaultsKey.lastFmEnabled)
        pendingToken = nil
        pendingAuthURL = nil
        statusMessage = "Ключи удалены."
        lastError = nil
    }

    // MARK: - Playback

    private func observePlayer() {
        player.$status
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .playing:
                    self.handleNowPlaying()
                case .idle, .error, .paused:
                    self.finalizeTrack()
                case .loading:
                    break
                }
            }
            .store(in: &cancellables)

        player.$nowPlaying
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.handleNowPlaying()
            }
            .store(in: &cancellables)

        player.$station
            .dropFirst()
            .sink { [weak self] _ in
                self?.finalizeTrack()
            }
            .store(in: &cancellables)
    }

    private func handleNowPlaying() {
        guard isEnabled,
              isConnected,
              let client,
              let sessionKey = credentials?.sessionKey,
              player.status == .playing
        else { return }
        guard let track = makeTrack() else { return }

        if activeTrack?.key != track.key {
            finalizeTrack()
            activeTrack = track
            activeStartedAt = Date()
            lastNowPlayingKey = nil
        }

        guard lastNowPlayingKey != track.key else { return }
        lastNowPlayingKey = track.key
        Task {
            await sendNowPlaying(track, client: client, sessionKey: sessionKey)
        }
    }

    private func makeTrack() -> Track? {
        guard let nowPlaying = player.nowPlaying,
              let artist = nowPlaying.displayArtist,
              let title = nowPlaying.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }

        let album = nowPlaying.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Track(
            artist: artist,
            title: title,
            album: album?.isEmpty == false ? album : nil,
            key: "\(artist.lowercased())|\(title.lowercased())"
        )
    }

    private func finalizeTrack() {
        guard let track = activeTrack, let startedAt = activeStartedAt else { return }
        activeTrack = nil
        activeStartedAt = nil
        lastNowPlayingKey = nil

        guard Self.shouldScrobble(elapsed: Date().timeIntervalSince(startedAt)),
              let client,
              let sessionKey = credentials?.sessionKey
        else { return }

        Task {
            await sendScrobble(
                track,
                startedAt: startedAt,
                client: client,
                sessionKey: sessionKey
            )
        }
    }

    private func sendNowPlaying(
        _ track: Track,
        client: LastFmClient,
        sessionKey: String
    ) async {
        do {
            try await client.updateNowPlaying(
                artist: track.artist,
                title: track.title,
                album: track.album,
                duration: nil,
                sessionKey: sessionKey
            )
            statusMessage = "Now playing: \(track.artist) — \(track.title)"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sendScrobble(
        _ track: Track,
        startedAt: Date,
        client: LastFmClient,
        sessionKey: String
    ) async {
        do {
            try await client.scrobble(
                artist: track.artist,
                title: track.title,
                album: track.album,
                timestamp: Int(startedAt.timeIntervalSince1970),
                duration: nil,
                sessionKey: sessionKey
            )
            statusMessage = "Скроббл: \(track.artist) — \(track.title)"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
