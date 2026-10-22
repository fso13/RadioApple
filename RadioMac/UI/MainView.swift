import AppKit
import SwiftUI

/// The main page: genre navigation and artwork on the left, station table on the
/// right, transport bar across the bottom.
struct MainView: View {
    @ObservedObject var model: MainViewModel
    @ObservedObject var library: StationLibrary
    @ObservedObject var player: RadioPlayerService
    @ObservedObject var equalizer: EqualizerService
    @ObservedObject var sleepTimer: SleepTimerService
    @ObservedObject var toasts: ToastCenter

    let onOpenSettings: () -> Void
    let onClose: () -> Void
    let onOpenEqualizer: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var pendingDelete: RadioStation?
    @State private var showRadioBrowser = false
    @State private var showTransfer = false

    @Environment(\.palette) private var palette

    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                header

                HStack(alignment: .top, spacing: Space.xxxl) {
                    sidebar
                    content
                }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.s)
                .frame(maxHeight: .infinity)

                playerBar
            }
            .overlay(alignment: .bottom) {
                ToastOverlay(center: toasts)
            }
        }
        .onChange(of: model.focusSearchToken) { _, _ in searchFocused = true }
        .onChange(of: model.resignSearchToken) { _, _ in searchFocused = false }
        .onChange(of: player.status) { _, newValue in
            guard newValue == .error else { return }
            toasts.show(player.consumeError() ?? "Не удалось открыть поток", kind: .error)
        }
        .sheet(isPresented: $showRadioBrowser) {
            RadioBrowserView(library: library, player: player, toasts: toasts)
        }
        .sheet(isPresented: $showTransfer) {
            StationTransferView(library: library, toasts: toasts)
        }
        .sheet(item: $model.editor) { request in
            StationEditorView(existing: request.station, genres: editorGenres) { draft in
                save(draft, existing: request.station)
            }
        }
        .alert(
            "Удалить станцию?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { station in
            Button("Отмена", role: .cancel) { pendingDelete = nil }
            Button("Удалить", role: .destructive) { delete(station) }
        } message: { station in
            Text("«\(station.name)» будет удалена из библиотеки.")
        }
    }

    // MARK: - Header

    private var header: some View {
        PanelHeader(showBrand: true) {
            PanelMenu {
                Button("Настройки…") { onOpenSettings() }
                Divider()
                Button("Скрыть окно") { onClose() }
                Button("Завершить RadioMac") { NSApp.terminate(nil) }
            }

            CircleIconButton(
                systemName: "xmark",
                size: 11,
                help: "Скрыть окно",
                action: onClose
            )
        }
    }

    // MARK: - Left column

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            GenreNav(model: model, library: library, player: player)

            HeroArtwork(
                station: player.station,
                artworkURL: player.nowPlaying?.artworkURL
            ) {
                player.togglePlayPause()
            }
        }
        .frame(width: 210)
    }

    // MARK: - Right column

    private var content: some View {
        VStack(spacing: 0) {
            SearchLine(text: $model.searchText, isFocused: $searchFocused)

            columnHeader
                .padding(.top, Space.m)
                .padding(.bottom, Space.xs)

            stationTable

            HStack(spacing: Space.m) {
                if model.canReorder {
                    Text("Перетащите строки, чтобы изменить порядок")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                TextButton(title: "Импорт/экспорт", systemImage: "arrow.up.arrow.down") {
                    showTransfer = true
                }
                TextButton(title: "Radio Browser", systemImage: "globe") {
                    showRadioBrowser = true
                }
                PrimaryButton(title: "Добавить станцию", systemImage: "plus") {
                    model.newStation()
                }
            }
            .padding(.top, Space.m)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: Space.s) {
            Color.clear.frame(width: 10, height: 10)
            Color.clear.frame(width: 20, height: 10)
            Text("СТАНЦИЯ").frame(maxWidth: .infinity, alignment: .leading)
            Text("ЖАНР").frame(width: 82, alignment: .leading)
            Color.clear.frame(width: 24, height: 10)
            Color.clear.frame(width: 24, height: 10)
        }
        .font(Typeface.overline)
        .tracking(1.2)
        .foregroundStyle(palette.textSecondary)
    }

    @ViewBuilder
    private var stationTable: some View {
        if model.visible.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, station in
                            stationRow(station, index: index)
                                .id(station.id)
                        }

                        if model.canReorder {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 14)
                                .contentShape(Rectangle())
                                .onDrop(of: [.text], isTargeted: nil) { providers in
                                    handleStationDrop(providers) { id in
                                        model.moveStationToEnd(id: id)
                                    }
                                }
                        }
                    }
                    .padding(.bottom, Space.s)
                }
                .scrollIndicators(.automatic)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Список станций")
                .accessibilityIdentifier("station-list")
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: model.selectedIndex) { _, index in
                    guard model.visible.indices.contains(index) else { return }
                    withAnimation(Motion.content) {
                        proxy.scrollTo(model.visible[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stationRow(_ station: RadioStation, index: Int) -> some View {
        let row = StationRow(
            station: station,
            index: index,
            isSelected: index == model.selectedIndex && model.keyboardNavigated,
            isCurrent: player.station?.id == station.id,
            isPlaying: player.station?.id == station.id && player.isPlaying,
            isLoading: player.station?.id == station.id && player.status == .loading,
            onPlay: {
                model.select(index)
                player.play(station)
            },
            onToggleFavorite: { model.toggleFavorite(station) },
            onEdit: { model.edit(station) },
            onDelete: { pendingDelete = station }
        )

        if model.canReorder {
            row
                .onDrag {
                    NSItemProvider(object: station.id as NSString)
                }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleStationDrop(providers) { id in
                        model.moveStation(id: id, before: station.id)
                    }
                }
        } else {
            row
        }
    }

    /// Loads the dragged station id and hands it to `onDrop` on the main queue.
    private func handleStationDrop(
        _ providers: [NSItemProvider],
        onDrop: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard model.canReorder, let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? NSString else { return }
            let id = value as String
            Task { @MainActor in onDrop(id) }
        }
        return true
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle,
            actionTitle: emptyActionTitle,
            action: emptyAction
        )
    }

    private var playerBar: some View {
        PlayerBar(
            player: player,
            equalizer: equalizer,
            sleepTimer: sleepTimer,
            onOpenEqualizer: onOpenEqualizer,
            onPrevious: { move(by: -1) },
            onNext: { move(by: 1) },
            canPrevious: canMove(by: -1),
            canNext: canMove(by: 1),
            canPlay: player.station != nil || player.isActive || !model.visible.isEmpty,
            onPlayFallback: {
                guard let first = model.visible.first else { return }
                model.select(0)
                player.play(first)
            }
        )
    }

    // MARK: - Navigation between stations

    private var currentIndex: Int? {
        guard let id = player.station?.id else { return nil }
        return model.visible.firstIndex { $0.id == id }
    }

    private func canMove(by delta: Int) -> Bool {
        guard let index = currentIndex else { return false }
        return model.visible.indices.contains(index + delta)
    }

    private func move(by delta: Int) {
        guard let index = currentIndex,
              model.visible.indices.contains(index + delta)
        else { return }
        player.play(model.visible[index + delta])
    }

    // MARK: - Empty state copy

    private var emptyIcon: String {
        if !model.searchText.isEmpty { return "magnifyingglass" }
        if model.filter == .favorites { return "star" }
        if case .group = model.filter { return "folder" }
        return "dot.radiowaves.left.and.right"
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return "Ничего не найдено" }
        if model.filter == .favorites { return "В избранном пусто" }
        if case .group = model.filter { return "В группе пусто" }
        return "Добавьте первую станцию"
    }

    private var emptySubtitle: String {
        if !model.searchText.isEmpty {
            return "Измените запрос или сбросьте фильтр."
        }
        if model.filter == .favorites {
            return "Отмечайте станции звёздочкой, чтобы они были под рукой."
        }
        if case .group = model.filter {
            return "Добавьте станции в группу через редактор станции."
        }
        return "Вставьте прямую ссылку на поток — название и жанр можно указать рядом."
    }

    private var emptyActionTitle: String? {
        if !model.searchText.isEmpty { return "Сбросить поиск" }
        if model.filter == .favorites { return "Показать все" }
        if case .group = model.filter { return "Показать все" }
        return "Добавить станцию"
    }

    private var emptyAction: (() -> Void)? {
        if !model.searchText.isEmpty {
            return {
                model.clearSearch()
                model.setFilter(.all)
            }
        }
        if model.filter == .favorites {
            return { model.setFilter(.all) }
        }
        if case .group = model.filter {
            return { model.setFilter(.all) }
        }
        return model.newStation
    }

    // MARK: - Editing

    private var editorGenres: [String] {
        var values = GenreCatalog.presets
        for genre in library.genres where !values.contains(genre) {
            values.append(genre)
        }
        return values
    }

    private func save(_ draft: StationDraft, existing: RadioStation?) {
        if var station = existing {
            station.name = draft.name
            station.url = draft.url
            station.genre = draft.genre
            station.comment = draft.comment.isEmpty ? nil : draft.comment
            station.group = draft.group.isEmpty ? nil : draft.group
            station.logoURL = draft.logoURL.isEmpty ? nil : draft.logoURL
            station.volumeOffsetDB = draft.volumeOffsetDB
            station.eqPresetID = draft.eqPresetID
            station.autoplay = draft.autoplay
            library.update(station)
            toasts.show("Станция сохранена", kind: .success)
        } else {
            library.add(
                name: draft.name,
                url: draft.url,
                genre: draft.genre,
                comment: draft.comment,
                group: draft.group,
                logoURL: draft.logoURL,
                volumeOffsetDB: draft.volumeOffsetDB,
                eqPresetID: draft.eqPresetID,
                autoplay: draft.autoplay
            )
            toasts.show("Станция добавлена", kind: .success)
        }
    }

    private func delete(_ station: RadioStation) {
        if player.station?.id == station.id {
            player.stop()
        }
        library.remove(id: station.id)
        pendingDelete = nil
        toasts.show("Станция удалена", kind: .success)
    }
}
