import Foundation

/// Commands accepted through the `radiomac://` URL scheme.
enum RadioURLCommand: Equatable, Sendable {
    case play(id: String)
    case pause
    case toggle
    case open

    static let scheme = "radiomac"

    static func parse(_ url: URL) -> RadioURLCommand? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        switch components.host?.lowercased() {
        case "play":
            let pathID = components.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let queryID = components.queryItems?
                .first(where: { $0.name == "id" })?
                .value
            let raw = pathID.isEmpty ? (queryID ?? "") : pathID
            let id = raw.removingPercentEncoding ?? raw
            guard !id.isEmpty else { return nil }
            return .play(id: id)
        case "pause":
            return .pause
        case "toggle":
            return .toggle
        case "open":
            return .open
        default:
            return nil
        }
    }
}
