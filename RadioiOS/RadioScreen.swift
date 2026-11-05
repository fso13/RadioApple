import SwiftUI

/// Station list: genres across the top, hairlines, the current station marked
/// with moving bars. A tap starts the stream; a long press edits or deletes.
struct RadioScreen: View {
    @ObservedObject var model: MainViewModel
    @Binding var showPlayer: Bool

    @EnvironmentObject private var library: StationLibrary
    @EnvironmentObject private var player: RadioPlayerService
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var pendingDeletion: RadioStation?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                overline: "Радио",
                title: filterTitle,
                subtitle: countLabel
            ) {
                CircleIconButton(
                    systemName: "plus",
                    size: 14,
                    help: "Добавить станцию"
                ) {
                    model.newStation()
                }
            }

            filterStrip
            SearchFieldIOS(text: $model.searchText, placeholder: "Станции, жанры, группы")
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)

            Hairline()

            if let error = player.errorMessage,
               player.status == .error || player.status == .reconnecting {
                InlineErrorBanner(message: error) {
                    player.retryNow()
                }
            }

            TabView(selection: $model.filter) {
                ForEach(filters, id: \.self) { filter in
                    stationPage(filter)
                        .tag(filter)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .sensoryFeedback(.selection, trigger: model.filter)
            .onChange(of: filters) { _, updated in
                if !updated.contains(model.filter) {
                    model.setFilter(.all)
                }
            }
        }
        .background(palette.window)
        .miniPlayer { showPlayer = true }
        .sensoryFeedback(.impact(weight: .light), trigger: player.station?.id)
        .sensoryFeedback(.selection, trigger: library.favorites.count)
        .sheet(item: $model.editor) { request in
            StationEditorView(existing: request.station, genres: library.genres) { draft in
                save(draft, into: request.station)
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "Удалить станцию?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { station in
            Button("Удалить", role: .destructive) {
                if player.station?.id == station.id {
                    player.stop()
                }
                library.remove(id: station.id)
                pendingDeletion = nil
            }
            Button("Отмена", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { station in
            Text("«\(station.name)» исчезнет из библиотеки. Стандартные станции можно вернуть в настройках.")
        }
    }

    // MARK: - Header

    private var filterTitle: String {
        switch model.filter {
        case .all: return "Все станции"
        case .favorites: return "Избранное"
        case .genre(let genre): return genre
        case .group(let group): return group
        }
    }

    private var countLabel: String {
        let count = model.visible.count
        let mod100 = count % 100
        let mod10 = count % 10
        if (11...14).contains(mod100) { return "\(count) станций" }
        switch mod10 {
        case 1: return "\(count) станция"
        case 2, 3, 4: return "\(count) станции"
        default: return "\(count) станций"
        }
    }

    // MARK: - Filters

    private var filters: [StationFilter] {
        [.all, .favorites]
            + library.genres.map(StationFilter.genre)
            + library.groups.map(StationFilter.group)
    }

    private var filterStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.l) {
                    FilterChip(title: "Все", isSelected: model.filter == .all) {
                        withAnimation(Motion.content) { model.setFilter(.all) }
                    }
                    .id(StationFilter.all)

                    FilterChip(title: "Избранное", isSelected: model.filter == .favorites) {
                        withAnimation(Motion.content) { model.setFilter(.favorites) }
                    }
                    .id(StationFilter.favorites)

                    ForEach(library.genres, id: \.self) { genre in
                        FilterChip(
                            title: genre,
                            isSelected: model.filter == .genre(genre)
                        ) {
                            withAnimation(Motion.content) { model.setFilter(.genre(genre)) }
                        }
                        .id(StationFilter.genre(genre))
                    }

                    if !library.groups.isEmpty {
                        groupsMenu
                    }
                }
                .padding(.horizontal, Space.l)
            }
            .onChange(of: model.filter) { _, filter in
                withAnimation(Motion.content) {
                    proxy.scrollTo(filter, anchor: .center)
                }
            }
        }
    }

    private var groupsMenu: some View {
        Menu {
            ForEach(library.groups, id: \.self) { group in
                Button {
                    withAnimation(Motion.content) { model.setFilter(.group(group)) }
                } label: {
                    if model.filter == .group(group) {
                        Label(group, systemImage: "checkmark")
                    } else {
                        Text(group)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(isGroupFilter ? currentGroupName : "Группы")
                    .font(.subheadline)
                    .fontWeight(isGroupFilter ? .semibold : .regular)
                    .foregroundStyle(isGroupFilter ? palette.textPrimary : palette.textTertiary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Группы станций")
    }

    private var isGroupFilter: Bool {
        if case .group = model.filter { return true }
        return false
    }

    private var currentGroupName: String {
        if case .group(let name) = model.filter { return name }
        return "Группы"
    }

    // MARK: - List

    @ViewBuilder
    private func stationPage(_ filter: StationFilter) -> some View {
        let items = model.stations(for: filter)

        if items.isEmpty {
            emptyState(for: filter)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, station in
                        row(station, number: index + 1)

                        Hairline(inset: 84)
                    }
                }
                .padding(.bottom, Space.m)
            }
            .refreshable {
                library.load()
            }
        }
    }

    private func emptyState(for filter: StationFilter) -> some View {
        VStack {
            Spacer(minLength: 0)
            EmptyStateView(
                systemImage: emptySystemImage(for: filter),
                title: emptyTitle(for: filter),
                subtitle: emptySubtitle(for: filter),
                actionTitle: filter == .favorites ? nil : "Добавить станцию",
                action: filter == .favorites ? nil : { model.newStation() }
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptySystemImage(for filter: StationFilter) -> String {
        switch filter {
        case .favorites: return "star"
        case .all, .genre, .group: return "dot.radiowaves.left.and.right"
        }
    }

    private func emptyTitle(for filter: StationFilter) -> String {
        if !model.searchText.isEmpty { return "Ничего не найдено" }
        switch filter {
        case .favorites: return "Пока нет избранных станций"
        case .all: return "Библиотека пуста"
        case .genre, .group: return "В этой подборке пусто"
        }
    }

    private func emptySubtitle(for filter: StationFilter) -> String {
        if !model.searchText.isEmpty {
            return "Попробуйте другое название, жанр или группу."
        }
        switch filter {
        case .favorites: return "Отмечайте станции звёздочкой — они соберутся здесь."
        case .all: return "Добавьте ссылку на поток или найдите станцию в каталоге."
        case .genre, .group: return "Выберите другую подборку или добавьте станцию."
        }
    }

    // MARK: - Row

    private func row(_ station: RadioStation, number: Int) -> some View {
        let isCurrent = player.station?.id == station.id
        let isPlaying = isCurrent && player.status == .playing

        return HStack(spacing: Space.m) {
            Button {
                player.play(station)
            } label: {
                HStack(spacing: Space.m) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(String(format: "%02d", number))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 22, alignment: .leading)
                    }

                    StationLogo(station: station, size: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                        Text(detail(for: station))
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }

                    Spacer(minLength: Space.s)

                    if isCurrent {
                        EqualizerBars(
                            isActive: isPlaying,
                            color: isPlaying ? palette.textPrimary : palette.textTertiary
                        )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Играть \(station.name)")

            Button {
                library.toggleFavorite(id: station.id)
            } label: {
                Image(systemName: station.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        station.isFavorite ? palette.textPrimary : palette.textTertiary
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                station.isFavorite ? "Убрать из избранного" : "В избранное"
            )
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: 66)
        .background(isCurrent ? palette.surfaceActive.opacity(0.55) : Color.clear)
        .contextMenu {
            Button {
                player.play(station)
            } label: {
                Label("Играть", systemImage: "play.fill")
            }

            Button {
                library.toggleFavorite(id: station.id)
            } label: {
                Label(
                    station.isFavorite ? "Убрать из избранного" : "В избранное",
                    systemImage: station.isFavorite ? "star.slash" : "star"
                )
            }

            Button {
                model.edit(station)
            } label: {
                Label("Изменить", systemImage: "pencil")
            }

            Button(role: .destructive) {
                pendingDeletion = station
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private func detail(for station: RadioStation) -> String {
        var parts: [String] = [station.genre]
        if let group = station.group, !group.isEmpty {
            parts.append(group)
        }
        if let comment = station.comment, !comment.isEmpty {
            parts.append(comment)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Saving

    private func save(_ draft: StationDraft, into existing: RadioStation?) {
        if var updated = existing {
            updated.name = draft.name
            updated.url = draft.url
            updated.genre = draft.genre
            updated.comment = draft.comment
            updated.group = draft.group
            updated.logoURL = draft.logoURL
            updated.volumeOffsetDB = draft.volumeOffsetDB
            updated.eqPresetID = draft.eqPresetID
            updated.autoplay = draft.autoplay
            library.update(updated)
        } else {
            _ = library.add(
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
        }
    }
}
