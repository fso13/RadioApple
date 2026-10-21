import AppIntents
import Foundation

// MARK: - Entity

struct RadioStationEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Станция")
    static let defaultQuery = RadioStationQuery()

    var id: String
    var name: String
    var genre: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(genre)")
    }

    init(station: RadioStation) {
        id = station.id
        name = station.name
        genre = station.genre
    }
}

struct RadioStationQuery: EntityQuery {
    func entities(for identifiers: [RadioStationEntity.ID]) async throws -> [RadioStationEntity] {
        let stations = await MainActor.run { AppRuntime.shared.stations }
        return identifiers.compactMap { id in
            stations.first(where: { $0.id == id }).map(RadioStationEntity.init)
        }
    }

    func suggestedEntities() async throws -> [RadioStationEntity] {
        let stations = await MainActor.run { AppRuntime.shared.stations }
        return stations.prefix(20).map(RadioStationEntity.init)
    }

    func defaultResult() async -> RadioStationEntity? {
        let stations = await MainActor.run { AppRuntime.shared.stations }
        return stations.first.map(RadioStationEntity.init)
    }
}

// MARK: - Intents

struct PlayStationIntent: AppIntent {
    static let title: LocalizedStringResource = "Играть станцию"
    static let description = IntentDescription("Включает выбранную станцию в RadioMac.")
    static let openAppWhenRun = false

    @Parameter(title: "Станция")
    var station: RadioStationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Играть \(\.$station)")
    }

    func perform() async throws -> some IntentResult {
        try await AppRuntime.shared.playStation(id: station.id)
        return .result()
    }
}

struct PauseRadioIntent: AppIntent {
    static let title: LocalizedStringResource = "Пауза"
    static let description = IntentDescription("Ставит текущую станцию на паузу.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await AppRuntime.shared.pause()
        return .result()
    }
}

struct OpenRadioIntent: AppIntent {
    static let title: LocalizedStringResource = "Открыть RadioMac"
    static let description = IntentDescription("Открывает главное окно RadioMac.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        try await AppRuntime.shared.openWindow()
        return .result()
    }
}

// MARK: - Shortcuts

struct RadioMacShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayStationIntent(),
            phrases: [
                "Играть \(\.$station) в \(.applicationName)",
                "Play \(\.$station) on \(.applicationName)",
            ],
            shortTitle: "Играть станцию",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseRadioIntent(),
            phrases: [
                "Пауза в \(.applicationName)",
                "Pause \(.applicationName)",
            ],
            shortTitle: "Пауза",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: OpenRadioIntent(),
            phrases: [
                "Открыть \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Открыть RadioMac",
            systemImageName: "macwindow"
        )
    }
}
