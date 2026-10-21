import Foundation

enum StationTransferFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case m3u
    case opml

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: return "JSON"
        case .m3u: return "M3U"
        case .opml: return "OPML"
        }
    }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .m3u: return "m3u"
        case .opml: return "opml"
        }
    }
}

enum StationImportMode: String, CaseIterable, Identifiable, Sendable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "Добавить"
        case .replace: return "Заменить"
        }
    }
}

struct StationImportResult: Equatable, Sendable {
    var added = 0
    var skipped = 0
    var favoritesUpdated = 0
}

enum StationTransferError: LocalizedError {
    case empty
    case unsupported
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "В файле нет станций."
        case .unsupported:
            return "Поддерживаются JSON, M3U и OPML."
        case .invalid(let reason):
            return "Не удалось прочитать файл: \(reason)"
        }
    }
}

enum StationTransfer {
    static func detectFormat(for url: URL) -> StationTransferFormat? {
        switch url.pathExtension.lowercased() {
        case "json": return .json
        case "m3u", "m3u8": return .m3u
        case "opml", "xml": return .opml
        default: return nil
        }
    }

    static func parse(data: Data, format: StationTransferFormat) throws -> [RadioStation] {
        switch format {
        case .json:
            return try parseJSON(data)
        case .m3u:
            return try parseM3U(data)
        case .opml:
            return try parseOPML(data)
        }
    }

    static func export(stations: [RadioStation], format: StationTransferFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(stations)
        case .m3u:
            return Data(exportM3U(stations).utf8)
        case .opml:
            return Data(exportOPML(stations).utf8)
        }
    }

    // MARK: - JSON

    private struct JSONPayload: Decodable {
        let stations: [RadioStation]
    }

    private static func parseJSON(_ data: Data) throws -> [RadioStation] {
        let decoder = JSONDecoder()
        let decoded: [RadioStation]
        if let array = try? decoder.decode([RadioStation].self, from: data) {
            decoded = array
        } else if let payload = try? decoder.decode(JSONPayload.self, from: data) {
            decoded = payload.stations
        } else {
            throw StationTransferError.invalid("ожидался массив станций")
        }
        return normalized(decoded)
    }

    // MARK: - M3U

    private static func parseM3U(_ data: Data) throws -> [RadioStation] {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            throw StationTransferError.invalid("не UTF-8")
        }

        var stations: [RadioStation] = []
        var pendingName: String?
        var pendingGroup: String?
        var pendingLogo: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.uppercased().hasPrefix("#EXTINF") {
                let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                pendingName = parts.count > 1
                    ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
                pendingGroup = attribute("group-title", in: line)
                pendingLogo = attribute("tvg-logo", in: line)
                continue
            }
            guard !line.hasPrefix("#") else { continue }

            guard let url = URL(string: line),
                  url.scheme?.isEmpty == false,
                  url.host?.isEmpty == false
            else { continue }

            let name = pendingName?.isEmpty == false ? pendingName! : (url.host ?? line)
            stations.append(
                RadioStation(
                    id: UUID().uuidString,
                    name: name,
                    url: line,
                    genre: pendingGroup ?? GenreCatalog.other,
                    comment: "Импорт M3U",
                    group: pendingGroup,
                    logoURL: pendingLogo
                )
            )
            pendingName = nil
            pendingGroup = nil
            pendingLogo = nil
        }

        guard !stations.isEmpty else { throw StationTransferError.empty }
        return normalized(stations)
    }

    private static func exportM3U(_ stations: [RadioStation]) -> String {
        var lines = ["#EXTM3U"]
        for station in stations {
            var attributes: [String] = []
            if let group = station.group, !group.isEmpty {
                attributes.append("group-title=\"\(escapeAttribute(group))\"")
            }
            if let logo = station.logoURL, !logo.isEmpty {
                attributes.append("tvg-logo=\"\(escapeAttribute(logo))\"")
            }
            attributes.append("tvg-name=\"\(escapeAttribute(station.name))\"")
            lines.append("#EXTINF:-1 \(attributes.joined(separator: " ")),\(station.name)")
            lines.append(station.url)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func attribute(_ name: String, in line: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ),
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range])
    }

    // MARK: - OPML

    private static func parseOPML(_ data: Data) throws -> [RadioStation] {
        let delegate = OPMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw StationTransferError.invalid("некорректный XML")
        }
        guard !delegate.stations.isEmpty else { throw StationTransferError.empty }
        return normalized(delegate.stations)
    }

    private static func exportOPML(_ stations: [RadioStation]) -> String {
        var grouped: [String: [RadioStation]] = [:]
        for station in stations {
            grouped[station.group ?? "Без группы", default: []].append(station)
        }
        let groups = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var outlines: [String] = []
        for group in groups {
            outlines.append("<outline text=\"\(escapeXML(group))\" title=\"\(escapeXML(group))\">")
            for station in grouped[group] ?? [] {
                outlines.append(
                    "  <outline type=\"link\" text=\"\(escapeXML(station.name))\" "
                        + "title=\"\(escapeXML(station.name))\" "
                        + "xmlUrl=\"\(escapeXML(station.url))\" "
                        + "category=\"\(escapeXML(station.genre))\""
                        + (station.comment.map { " description=\"\(escapeXML($0))\"" } ?? "")
                        + "/>"
                )
            }
            outlines.append("</outline>")
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>RadioMac</title></head>
          <body>
        \(outlines.joined(separator: "\n"))
          </body>
        </opml>

        """
    }

    private static func normalized(_ input: [RadioStation]) -> [RadioStation] {
        input.compactMap { source in
            let url = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = URL(string: url),
                  parsed.scheme?.isEmpty == false,
                  parsed.host?.isEmpty == false
            else { return nil }
            var station = source
            if station.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                station.id = UUID().uuidString
            }
            if station.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                station.name = parsed.host ?? url
            }
            station.url = url
            station.genre = GenreCatalog.normalize(station.genre)
            return station
        }
    }

    private static func escapeAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'")
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private final class OPMLDelegate: NSObject, XMLParserDelegate {
    var stations: [RadioStation] = []
    private var group: String?
    private var groupDepth: Int?
    private var depth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }
        defer { depth += 1 }

        let name = attributes["text"] ?? attributes["title"] ?? ""
        let stream = attributes["xmlUrl"] ?? attributes["url"] ?? ""

        if stream.isEmpty {
            if group == nil {
                group = name
                groupDepth = depth
            }
            return
        }

        guard let url = URL(string: stream),
              url.scheme?.isEmpty == false,
              url.host?.isEmpty == false
        else { return }

        stations.append(
            RadioStation(
                id: UUID().uuidString,
                name: name.isEmpty ? (url.host ?? stream) : name,
                url: stream,
                genre: attributes["category"] ?? group ?? GenreCatalog.other,
                comment: attributes["description"],
                group: group,
                logoURL: attributes["tvg-logo"] ?? attributes["logo"]
            )
        )
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline" else { return }
        depth = max(0, depth - 1)
        if groupDepth == depth {
            group = nil
            groupDepth = nil
        }
    }
}
