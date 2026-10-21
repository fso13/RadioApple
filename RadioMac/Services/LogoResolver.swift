import Foundation

/// Finds a station logo from the stream URL (and optional homepage / name).
///
/// Stream hosts are often CDNs, so the resolver:
/// 1. asks Radio Browser for a favicon matching the stream,
/// 2. tries the station homepage from ICY metadata,
/// 3. falls back to a favicon for the stream's brand domain.
final class LogoResolver {
    static let shared = LogoResolver()

    private let radioBrowser = "https://de1.api.radio-browser.info"
    private let userAgent = "RadioMac/1.0"
    private let session: URLSession

    private static let cdnHosts: Set<String> = [
        "hostingradio.ru",
        "cdnvideo.ru",
        "streamguys1.com",
        "getradio.me",
        "mediacdn.ru",
        "101.ru",
        "amgradio.ru",
        "volna.top",
        "radio-holding.ru",
        "vdfm.ru",
    ]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.httpAdditionalHeaders = ["User-Agent": "RadioMac/1.0"]
        session = URLSession(configuration: configuration)
    }

    func resolve(streamURL: String, homepage: String?, name: String?) async -> String? {
        if let fromCatalog = await fromRadioBrowser(streamURL: streamURL, name: name) {
            return fromCatalog
        }

        var hosts: [String] = []
        if let homeHost = Self.hostOf(homepage) {
            hosts.append(homeHost)
        }
        if let brand = Self.brandHost(Self.hostOf(streamURL)) {
            hosts.append(brand)
        }

        for host in hosts {
            let candidate = "https://www.google.com/s2/favicons?sz=128&domain=\(host)"
            if await looksLikeImage(candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Radio Browser

    private func fromRadioBrowser(streamURL: String, name: String?) async -> String? {
        let byURL = await searchRadioBrowser(["url": streamURL])
        if let favicon = Self.bestFavicon(byURL) { return favicon }

        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.count >= 3
        else { return nil }
        let byName = await searchRadioBrowser(["name": trimmed, "countrycode": "RU"])
        return Self.bestFavicon(byName)
    }

    private func searchRadioBrowser(_ parameters: [String: String]) async -> [[String: Any]] {
        var components = URLComponents(string: "\(radioBrowser)/json/stations/search")
        var query: [URLQueryItem] = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        query.append(contentsOf: [
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: "5"),
        ])
        components?.queryItems = query
        guard let url = components?.url else { return [] }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            return json
        } catch {
            return []
        }
    }

    static func bestFavicon(_ stations: [[String: Any]]) -> String? {
        for station in stations {
            guard let raw = (station["favicon"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty, raw != "null",
                let url = URL(string: raw), url.scheme != nil,
                url.scheme == "http" || url.scheme == "https"
            else { continue }
            return raw
        }
        return nil
    }

    private func looksLikeImage(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 6
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode)
            else { return false }
            let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            return type.hasPrefix("image/")
        } catch {
            return false
        }
    }

    // MARK: - Host helpers

    static func hostOf(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty
        else { return nil }
        return host.lowercased()
    }

    /// Drops CDN hosts; `ice1.somafm.com` → `somafm.com`.
    static func brandHost(_ host: String?) -> String? {
        guard let host, !host.isEmpty else { return nil }
        for cdn in cdnHosts where host == cdn || host.hasSuffix(".\(cdn)") {
            return nil
        }
        let parts = host.components(separatedBy: ".")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: ".")
        }
        return host
    }
}
