import SwiftUI

/// A single radio stream in the library.
struct RadioStation: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var url: String
    var genre: String
    var comment: String?
    var logoURL: String?
    var isFavorite: Bool
    var builtIn: Bool

    init(
        id: String,
        name: String,
        url: String,
        genre: String,
        comment: String? = nil,
        logoURL: String? = nil,
        isFavorite: Bool = false,
        builtIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.genre = genre
        self.comment = comment
        self.logoURL = logoURL
        self.isFavorite = isFavorite
        self.builtIn = builtIn
    }

    var hasComment: Bool {
        guard let comment else { return false }
        return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasLogo: Bool {
        guard let logoURL else { return false }
        return !logoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var streamURL: URL? {
        guard let url = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.isEmpty == false,
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    // MARK: - JSON

    private enum CodingKeys: String, CodingKey {
        case id, name, url, genre, comment, logoUrl, isFavorite, builtIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        genre = GenreCatalog.normalize(
            try container.decodeIfPresent(String.self, forKey: .genre) ?? GenreCatalog.other
        )
        comment = RadioStation.emptyToNil(try container.decodeIfPresent(String.self, forKey: .comment))
        logoURL = RadioStation.emptyToNil(try container.decodeIfPresent(String.self, forKey: .logoUrl))
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        builtIn = try container.decodeIfPresent(Bool.self, forKey: .builtIn) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(genre, forKey: .genre)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(logoURL, forKey: .logoUrl)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(builtIn, forKey: .builtIn)
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// The fixed genre vocabulary plus helpers for colours and normalisation.
enum GenreCatalog {
    static let jazz = "Jazz"
    static let electronic = "Electronic"
    static let rock = "Rock"
    static let classical = "Classical"
    static let news = "News"
    static let ambient = "Ambient"
    static let pop = "Pop"
    static let chill = "Chill"
    static let folk = "Folk"
    static let world = "World"
    static let shanson = "Shanson"
    static let retro = "Retro"
    static let other = "Other"

    static let presets: [String] = [
        jazz, electronic, rock, classical, news, ambient, pop,
        chill, folk, world, shanson, retro, other,
    ]

    /// Keeps known genres in their canonical casing, passes custom ones through.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return other }
        if let preset = presets.first(where: { $0.lowercased() == trimmed.lowercased() }) {
            return preset
        }
        return trimmed
    }

}
