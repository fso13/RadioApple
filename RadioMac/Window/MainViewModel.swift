import Combine
import Foundation

enum StationFilter: Equatable {
    case all
    case favorites
    case genre(String)
}

enum StationEditorRequest: Identifiable {
    case new
    case existing(RadioStation)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let station): return station.id
        }
    }

    var station: RadioStation? {
        switch self {
        case .new: return nil
        case .existing(let station): return station
        }
    }
}

/// UI state for the main panel: search text, genre filter, keyboard selection
/// and the station editor sheet.
final class MainViewModel: ObservableObject {
    private let library: StationLibrary
    private var cancellables: Set<AnyCancellable> = []

    @Published var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            recompute(resetSelection: true)
        }
    }

    @Published var filter: StationFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            recompute(resetSelection: true)
        }
    }

    @Published private(set) var visible: [RadioStation] = []
    @Published private(set) var selectedIndex: Int = 0
    /// True once the user moved the selection with the keyboard.
    @Published private(set) var keyboardNavigated = false

    /// Incremented to ask the view to focus the search field (⌘F).
    @Published private(set) var focusSearchToken = 0
    /// Incremented to ask the view to give up search focus (Esc).
    @Published private(set) var resignSearchToken = 0

    @Published var editor: StationEditorRequest?

    init(library: StationLibrary) {
        self.library = library
        library.$stations
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute(resetSelection: false) }
            .store(in: &cancellables)
        recompute(resetSelection: true)
    }

    // MARK: - Filtering

    private func recompute(resetSelection: Bool) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let items = library.stations.filter { station in
            switch filter {
            case .all:
                break
            case .favorites:
                if !station.isFavorite { return false }
            case .genre(let genre):
                if GenreCatalog.normalize(station.genre) != genre { return false }
            }

            guard !query.isEmpty else { return true }
            let haystacks = [
                station.name.lowercased(),
                station.genre.lowercased(),
                station.url.lowercased(),
                station.comment?.lowercased() ?? "",
            ]
            return haystacks.contains { $0.contains(query) }
        }

        visible = items

        if resetSelection {
            selectedIndex = 0
            keyboardNavigated = false
        } else {
            selectedIndex = clamped(selectedIndex)
        }
    }

    private func clamped(_ index: Int) -> Int {
        guard !visible.isEmpty else { return 0 }
        return min(max(0, index), visible.count - 1)
    }

    func select(_ index: Int) {
        guard !visible.isEmpty else { return }
        selectedIndex = clamped(index)
    }

    func moveSelection(_ delta: Int) {
        guard !visible.isEmpty else { return }
        selectedIndex = clamped(selectedIndex + delta)
        keyboardNavigated = true
    }

    func playSelected(using player: RadioPlayerService) {
        playVisible(at: selectedIndex, using: player)
    }

    func playVisible(at index: Int, using player: RadioPlayerService) {
        guard visible.indices.contains(index) else { return }
        player.play(visible[index])
    }

    func toggleFavorite(_ station: RadioStation) {
        library.toggleFavorite(id: station.id)
    }

    // MARK: - Intents

    func focusSearch() {
        focusSearchToken += 1
    }

    func resignSearch() {
        resignSearchToken += 1
    }

    func clearSearch() {
        searchText = ""
    }

    func setFilter(_ value: StationFilter) {
        filter = value
    }

    /// Mirrors the Flutter app: hiding the panel resets search, filter and selection.
    func resetAfterHide() {
        editor = nil
        searchText = ""
        filter = .all
        selectedIndex = 0
        keyboardNavigated = false
    }

    func newStation() {
        editor = .new
    }

    func edit(_ station: RadioStation) {
        editor = .existing(station)
    }
}
