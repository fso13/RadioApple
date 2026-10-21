import Foundation

/// One station returned by the Radio Browser directory.
struct RadioBrowserStation: Decodable, Identifiable, Sendable {
    let stationuuid: String
    let name: String
    let url: String?
    let urlResolved: String?
    let homepage: String?
    let favicon: String?
    let tags: String?
    let country: String?
    let codec: String?
    let bitrate: Int?

    var id: String { stationuuid }

    var streamURL: String? {
        for candidate in [urlResolved, url] {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let parsed = URL(string: value),
                  parsed.scheme?.isEmpty == false,
                  parsed.host?.isEmpty == false
            else { continue }
            return value
        }
        return nil
    }

    var genre: String {
        let first = tags?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return first ?? GenreCatalog.other
    }

    var details: String {
        var parts: [String] = []
        if let country, !country.isEmpty { parts.append(country) }
        if let codec, !codec.isEmpty { parts.append(codec.uppercased()) }
        if let bitrate, bitrate > 0 { parts.append("\(bitrate) kbps") }
        return parts.joined(separator: " · ")
    }

    func asRadioStation() -> RadioStation {
        RadioStation(
            id: "rb-\(stationuuid)",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: streamURL ?? "",
            genre: genre,
            comment: details.isEmpty ? "Radio Browser" : "Radio Browser · \(details)",
            logoURL: favicon,
            externalID: stationuuid
        )
    }

    private enum CodingKeys: String, CodingKey {
        case stationuuid
        case name
        case url
        case urlResolved = "url_resolved"
        case homepage
        case favicon
        case tags
        case country
        case codec
        case bitrate
    }
}

enum RadioBrowserError: LocalizedError {
    case emptyQuery
    case badResponse(Int)
    case noResults

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Введите название, жанр или страну."
        case .badResponse(let status):
            return "Radio Browser вернул ошибку \(status)."
        case .noResults:
            return "Станции не найдены. Попробуйте другой запрос."
        }
    }
}

/// Search client for the public Radio Browser directory.
@MainActor
final class RadioBrowserService: ObservableObject {
    @Published private(set) var results: [RadioBrowserStation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String = ""

    private var task: Task<Void, Never>?

    func search(name: String, genre: String, country: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = country.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty || !genre.isEmpty || !country.isEmpty else {
            task?.cancel()
            results = []
            isLoading = false
            errorText = RadioBrowserError.emptyQuery.errorDescription ?? ""
            return
        }

        task?.cancel()
        isLoading = true
        errorText = ""
        task = Task { @MainActor [weak self] in
            do {
                let stations = try await Self.fetch(
                    name: name,
                    genre: genre,
                    country: country
                )
                guard !Task.isCancelled, let self else { return }
                results = stations
                isLoading = false
                if stations.isEmpty {
                    errorText = RadioBrowserError.noResults.errorDescription ?? ""
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                isLoading = false
                errorText = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    nonisolated private static func fetch(
        name: String,
        genre: String,
        country: String
    ) async throws -> [RadioBrowserStation] {
        var components = URLComponents(
            string: "https://de1.api.radio-browser.info/json/stations/search"
        )!
        var items = [
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        if !name.isEmpty { items.append(URLQueryItem(name: "name", value: name)) }
        if !genre.isEmpty { items.append(URLQueryItem(name: "tag", value: genre)) }
        if !country.isEmpty { items.append(URLQueryItem(name: "country", value: country)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("RadioMac/1.0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: RadioBrowserError.badResponse(0))
                    return
                }
                guard http.statusCode == 200 else {
                    continuation.resume(throwing: RadioBrowserError.badResponse(http.statusCode))
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
            .resume()
        }
        return try JSONDecoder().decode([RadioBrowserStation].self, from: data)
    }
}
