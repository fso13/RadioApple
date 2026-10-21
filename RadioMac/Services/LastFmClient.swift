import CryptoKit
import Foundation

struct LastFmSession: Sendable {
    let username: String
    let key: String
}

enum LastFmError: LocalizedError, Sendable {
    case network(String)
    case api(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .network(let message):
            return "Last.fm: \(message)"
        case .api(_, let message):
            return "Last.fm: \(message)"
        case .decoding:
            return "Last.fm вернул неожиданный ответ."
        }
    }
}

/// Minimal Last.fm 2.0 client: desktop auth, now-playing and scrobbling.
///
/// API keys are entered by the user in Settings, so the app contains no
/// developer secret. The client is stateless and safe to use from any task.
final class LastFmClient: @unchecked Sendable {
    private let apiKey: String
    private let apiSecret: String
    private let session: URLSession
    private let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    init(apiKey: String, apiSecret: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.session = session
    }

    func requestToken() async throws -> String {
        let response: TokenResponse = try await post([
            "method": "auth.getToken",
            "api_key": apiKey,
        ])
        return response.token
    }

    func session(token: String) async throws -> LastFmSession {
        let response: SessionResponse = try await post([
            "method": "auth.getSession",
            "api_key": apiKey,
            "token": token,
        ])
        return LastFmSession(username: response.session.name, key: response.session.key)
    }

    func authURL(token: String) throws -> URL {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token),
        ]
        guard let url = components?.url else {
            throw LastFmError.network("не удалось собрать ссылку авторизации")
        }
        return url
    }

    func updateNowPlaying(
        artist: String,
        title: String,
        album: String?,
        duration: Int?,
        sessionKey: String
    ) async throws {
        var params = [
            "method": "track.updateNowPlaying",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": title,
        ]
        if let album, !album.isEmpty { params["album"] = album }
        if let duration, duration > 0 { params["duration"] = String(duration) }
        let _: EmptyResponse = try await post(params)
    }

    func scrobble(
        artist: String,
        title: String,
        album: String?,
        timestamp: Int,
        duration: Int?,
        sessionKey: String
    ) async throws {
        var params = [
            "method": "track.scrobble",
            "api_key": apiKey,
            "sk": sessionKey,
            "artist": artist,
            "track": title,
            "timestamp": String(timestamp),
        ]
        if let album, !album.isEmpty { params["album"] = album }
        if let duration, duration > 0 { params["duration"] = String(duration) }
        let _: EmptyResponse = try await post(params)
    }

    // MARK: - Request

    private func post<T: Decodable & Sendable>(_ params: [String: String]) async throws -> T {
        var signed = params.filter { $0.key != "format" && $0.key != "api_sig" }
        signed["api_sig"] = Self.signature(signed, secret: apiSecret)

        var body = signed
        body["format"] = "json"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formBody(body).data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LastFmError.network("нет HTTP-ответа")
            }
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw LastFmError.api(apiError.error, apiError.message)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw LastFmError.network("HTTP \(http.statusCode)")
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw LastFmError.decoding
            }
        } catch let error as LastFmError {
            throw error
        } catch {
            throw LastFmError.network(error.localizedDescription)
        }
    }

    static func signature(_ params: [String: String], secret: String) -> String {
        let filtered = params.filter { $0.key != "format" && $0.key != "api_sig" }
        let base = filtered.keys.sorted()
            .map { "\($0)\(filtered[$0] ?? "")" }
            .joined() + secret
        let digest = Insecure.MD5.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func formBody(_ params: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }

    // MARK: - Responses

    private struct APIError: Decodable, Sendable {
        let error: Int
        let message: String
    }

    private struct TokenResponse: Decodable, Sendable {
        let token: String
    }

    private struct SessionResponse: Decodable, Sendable {
        struct Session: Decodable, Sendable {
            let name: String
            let key: String
        }
        let session: Session
    }

    private struct EmptyResponse: Decodable, Sendable {
        init(from decoder: Decoder) throws {}
    }
}
