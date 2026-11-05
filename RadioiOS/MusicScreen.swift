import SwiftUI
import UniformTypeIdentifiers

/// Local music: tracks, albums, artists and playlists over one shared library.
///
/// Files picked in the Files app are copied into the app container; metadata
/// can be edited by hand or pulled from Apple Music/Deezer. Nothing is written
/// back to the audio files.
struct MusicScreen: View {
    @ObservedObject var model: MusicViewModel
    @Binding var showPlayer: Bool

    @EnvironmentObject private var music: MusicLibrary
    @EnvironmentObject private var player: RadioPlayerService
    @EnvironmentObject private var router: IOSRouter
    @Environment(\.palette) private var palette

    @State private var path: [MusicRoute] = []
    @State private var importing = false
    @State private var isCopying = false
    @State private var alertText: String?

    @State private var trackEditor: LocalTrack?
    @State private var artworkEditor: MusicArtworkEditor?
    @State private var playlistPrompt: PlaylistPromptRequest?
    @State private var trackPickerPlaylist: MusicPlaylist?
    @State private var pendingDelete: LocalTrack?
    @State private var pendingPlaylistDelete: MusicPlaylist?
    @State private var isSelecting = false
    @State private var selectedTrackIDs: Set<String> = []
    @State private var confirmDeleteSelection = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                pagePicker

                SearchFieldIOS(text: $model.searchText, placeholder: searchPlaceholder)
                    .padding(.top, Space.m)
                    .padding(.bottom, Space.s)

                Hairline()

                if isSelecting {
                    selectionBar
                }

                if isCopying || music.isScanning || music.isEnriching {
                    progressBar
                }

                TabView(selection: $model.page) {
                    ForEach(MusicPage.allCases) { page in
                        pageBody(page)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .sensoryFeedback(.selection, trigger: model.page)
                .onChange(of: model.page) { _, page in
                    if page != .allTracks { exitSelection() }
                }
                .onChange(of: model.searchText) { _, _ in
                    if isSelecting { selectedTrackIDs.removeAll() }
                }
            }
            .background(palette.window)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MusicRoute.self) { route in
                destination(for: route)
            }
        }
        .miniPlayer { showPlayer = true }
        .sensoryFeedback(.impact(weight: .light), trigger: player.localTrack?.id)
        .task(id: router.musicPage) {
            guard let page = router.musicPage else { return }
            model.show(page)
            router.musicPage = nil
        }
        .task(id: router.playlistName) {
            guard let name = router.playlistName else { return }
            router.playlistName = nil
            guard let playlist = music.playlists.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else { return }
            path.append(.playlist(playlist.id))
        }
        .task(id: router.albumTitle) {
            guard let title = router.albumTitle else { return }
            router.albumTitle = nil
            guard let album = music.albums.first(where: {
                $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
            }) else { return }
            path.append(.album(album.id))
        }
        .task(id: router.artistName) {
            guard let name = router.artistName else { return }
            router.artistName = nil
            guard let artist = music.artists.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else { return }
            path.append(.artist(artist.id))
        }
        .task(id: router.importSharedMusic) {
            guard router.importSharedMusic else { return }
            router.importSharedMusic = false
            importSharedFiles()
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(item: $trackEditor) { track in
            MusicTrackEditorScreen(track: track)
                .presentationDetents([.large])
        }
        .sheet(item: $artworkEditor) { editor in
            MusicArtworkEditorScreen(editor: editor)
                .presentationDetents([.large])
        }
        .sheet(item: $playlistPrompt) { request in
            MusicPlaylistNameSheet(request: request) { name in
                switch request.mode {
                case .create(let trackIDs):
                    music.createPlaylist(name: name, trackIDs: trackIDs)
                case .rename(let playlist):
                    music.renamePlaylist(id: playlist.id, name: name)
                }
            }
        }
        .sheet(item: $trackPickerPlaylist) { playlist in
            MusicTrackPickerSheet(playlist: playlist)
        }
        .alert(
            "Импорт музыки",
            isPresented: Binding(
                get: { alertText != nil },
                set: { if !$0 { alertText = nil } }
            )
        ) {
            Button("OK", role: .cancel) { alertText = nil }
        } message: {
            Text(alertText ?? "")
        }
        .confirmationDialog(
            "Удалить трек?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { track in
            Button("Удалить", role: .destructive) {
                delete(track)
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) {
                pendingDelete = nil
            }
        } message: { track in
            Text("«\(track.displayTitle)» исчезнет из библиотеки и плейлистов. Файл останется на устройстве.")
        }
        .confirmationDialog(
            "Удалить выбранные треки?",
            isPresented: $confirmDeleteSelection
        ) {
            Button("Удалить", role: .destructive) {
                deleteSelectedTracks()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(
                "Выбрано \(selectedTrackIDs.count) \(trackWord(selectedTrackIDs.count)). "
                    + "Треки исчезнут из библиотеки и плейлистов, но файлы останутся на устройстве."
            )
        }
        .confirmationDialog(
            "Удалить плейлист?",
            isPresented: Binding(
                get: { pendingPlaylistDelete != nil },
                set: { if !$0 { pendingPlaylistDelete = nil } }
            ),
            presenting: pendingPlaylistDelete
        ) { playlist in
            Button("Удалить", role: .destructive) {
                delete(playlist)
                pendingPlaylistDelete = nil
            }
            Button("Отмена", role: .cancel) {
                pendingPlaylistDelete = nil
            }
        } message: { playlist in
            Text("«\(playlist.name)» будет удалён. Треки останутся в библиотеке.")
        }
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader(
            overline: "Локальные файлы",
            title: "Моя музыка",
            subtitle: subtitle
        ) {
            if isSelecting {
                TextButton(title: "Отмена") { exitSelection() }
            } else {
                if model.page == .allTracks {
                    sortMenu
                    if !visibleTracks.isEmpty {
                        TextButton(title: "Выбрать") { beginSelection() }
                    }
                }

                libraryMenu

                if model.page != .allTracks {
                    CircleIconButton(systemName: "plus", size: 14, help: addButtonTitle) {
                        addButtonAction()
                    }
                }
            }
        }
    }

    private var subtitle: String {
        switch model.page {
        case .allTracks: return MusicCount.tracks(visibleTracks.count)
        case .albums: return MusicCount.albums(filteredAlbums.count)
        case .artists: return MusicCount.artists(filteredArtists.count)
        case .playlists: return MusicCount.playlists(filteredPlaylists.count)
        }
    }

    private var searchPlaceholder: String {
        switch model.page {
        case .allTracks: return "Название, исполнитель, альбом"
        case .albums: return "Альбом или исполнитель"
        case .artists: return "Исполнитель"
        case .playlists: return "Название плейлиста"
        }
    }

    private var addButtonTitle: String {
        model.page == .playlists ? "Создать плейлист" : "Импортировать музыку"
    }

    private func addButtonAction() {
        if model.page == .playlists {
            actions.createPlaylist()
        } else {
            importing = true
        }
    }

    private var selectionBar: some View {
        HStack(spacing: Space.m) {
            Button(allVisibleSelected ? "Снять выбор" : "Выбрать все") {
                toggleSelectAll()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.textPrimary)
            .frame(minHeight: 44)

            Spacer(minLength: Space.s)

            Text("Выбрано: \(selectedTrackIDs.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.textSecondary)

            Button(role: .destructive) {
                confirmDeleteSelection = true
            } label: {
                Label("Удалить", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        selectedTrackIDs.isEmpty ? palette.textTertiary : palette.red
                    )
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(selectedTrackIDs.isEmpty)
        }
        .padding(.horizontal, Space.l)
        .background(palette.surfaceRaised)
        .overlay(alignment: .bottom) { Hairline() }
        .sensoryFeedback(.selection, trigger: selectedTrackIDs.count)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Сортировка", selection: $model.sort) {
                ForEach(MusicSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Сортировка")
    }

    private var libraryMenu: some View {
        Menu {
            Button {
                music.startEnrichment()
            } label: {
                Label("Обогатить метаданные", systemImage: "sparkles")
            }
            .disabled(music.isEnriching)

            if music.isEnriching {
                Button {
                    music.cancelEnrichment()
                } label: {
                    Label("Остановить обогащение", systemImage: "stop.circle")
                }
            }

            Button {
                music.rescan()
            } label: {
                Label("Обновить библиотеку", systemImage: "arrow.clockwise")
            }

            Divider()

            Button {
                actions.createPlaylist()
            } label: {
                Label("Новый плейлист", systemImage: "music.note.list")
            }

            Button {
                importing = true
            } label: {
                Label("Импортировать музыку", systemImage: "square.and.arrow.down")
            }

            Button {
                importSharedFiles()
            } label: {
                Label("Импортировать из папки RadioMac/Music", systemImage: "folder")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ещё")
    }

    private var pagePicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.l) {
                    ForEach(MusicPage.allCases) { page in
                        FilterChip(title: pageTitle(page), isSelected: model.page == page) {
                            withAnimation(Motion.content) { model.page = page }
                        }
                        .id(page)
                    }
                }
                .padding(.horizontal, Space.l)
            }
            .onChange(of: model.page) { _, page in
                withAnimation(Motion.content) {
                    proxy.scrollTo(page, anchor: .center)
                }
            }
        }
    }

    private func pageTitle(_ page: MusicPage) -> String {
        switch page {
        case .allTracks: return "Треки"
        case .albums: return "Альбомы"
        case .artists: return "Артисты"
        case .playlists: return "Плейлисты"
        }
    }

    private var progressBar: some View {
        HStack(spacing: Space.s) {
            ProgressView()
                .controlSize(.small)

            Text(progressText)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(palette.surfaceRaised)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var progressText: String {
        if isCopying { return "Копирую файлы в приложение…" }
        return music.scanStatus ?? music.enrichmentStatus ?? "Обновляю библиотеку…"
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageBody(_ page: MusicPage) -> some View {
        switch page {
        case .allTracks:
            if visibleTracks.isEmpty {
                emptyState(
                    systemImage: "music.note",
                    title: music.tracks.isEmpty ? "Музыки пока нет" : "Ничего не найдено",
                    subtitle: music.tracks.isEmpty
                        ? "Выберите файлы или папку в «Файлах» — приложение скопирует их и прочитает теги."
                        : "Попробуйте другое название, исполнителя или альбом.",
                    actionTitle: music.tracks.isEmpty ? "Импортировать музыку" : nil,
                    action: music.tracks.isEmpty ? { importing = true } : nil
                )
            } else {
                ScrollView {
                    MusicTrackListIOS(
                        tracks: visibleTracks,
                        queueTitle: "Моя музыка",
                        isSelecting: isSelecting,
                        selectedIDs: selectedTrackIDs,
                        onToggleSelection: toggleSelection,
                        actions: actions
                    )
                    .padding(.bottom, Space.m)
                }
                .refreshable {
                    music.rescan()
                }
            }

        case .albums:
            if filteredAlbums.isEmpty {
                emptyState(
                    systemImage: "square.stack",
                    title: music.albums.isEmpty ? "Альбомов пока нет" : "Ничего не найдено",
                    subtitle: music.albums.isEmpty
                        ? "Альбомы собираются из тегов треков после импорта."
                        : "Попробуйте другое название или исполнителя."
                )
            } else {
                MusicAlbumsGrid(albums: filteredAlbums, actions: actions)
            }

        case .artists:
            if filteredArtists.isEmpty {
                emptyState(
                    systemImage: "person",
                    title: music.artists.isEmpty ? "Исполнителей пока нет" : "Ничего не найдено",
                    subtitle: music.artists.isEmpty
                        ? "Исполнители собираются из тегов треков после импорта."
                        : "Попробуйте другое имя."
                )
            } else {
                MusicArtistsGrid(artists: filteredArtists, actions: actions)
            }

        case .playlists:
            if filteredPlaylists.isEmpty {
                emptyState(
                    systemImage: "music.note.list",
                    title: music.playlists.isEmpty ? "Плейлистов пока нет" : "Ничего не найдено",
                    subtitle: music.playlists.isEmpty
                        ? "Соберите подборку из треков библиотеки — файлы не копируются."
                        : "Попробуйте другое название.",
                    actionTitle: music.playlists.isEmpty ? "Создать плейлист" : nil,
                    action: music.playlists.isEmpty ? { actions.createPlaylist() } : nil
                )
            } else {
                MusicPlaylistsGrid(playlists: filteredPlaylists, actions: actions)
            }
        }
    }

    private func emptyState(
        systemImage: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack {
            Spacer(minLength: 0)
            EmptyStateView(
                systemImage: systemImage,
                title: title,
                subtitle: subtitle,
                actionTitle: actionTitle,
                action: action
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func destination(for route: MusicRoute) -> some View {
        switch route {
        case .album(let id):
            MusicAlbumDetailScreen(albumID: id, actions: actions)
        case .artist(let id):
            MusicArtistDetailScreen(artistID: id, actions: actions)
        case .playlist(let id):
            MusicPlaylistDetailScreen(playlistID: id, actions: actions)
        }
    }

    // MARK: - Derived

    private var query: String {
        model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ text: String) -> Bool {
        guard !query.isEmpty else { return true }
        return text.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private var visibleTracks: [LocalTrack] {
        music.filteredTracks(query: model.searchText, playlistID: nil, sort: model.sort)
    }

    private var filteredAlbums: [MusicAlbum] {
        guard !query.isEmpty else { return music.albums }
        return music.albums.filter { matches($0.searchText) }
    }

    private var filteredArtists: [MusicArtist] {
        guard !query.isEmpty else { return music.artists }
        return music.artists.filter { matches($0.searchText) }
    }

    private var filteredPlaylists: [MusicPlaylist] {
        guard !query.isEmpty else { return music.playlists }
        return music.playlists.filter { matches($0.name) }
    }
}

extension MusicScreen {
    // MARK: - Actions

    private var actions: MusicActions {
        MusicActions(
            play: { track, queue, title in
                player.playLocal(track, queue: queue, title: title)
            },
            playAlbum: { album in
                guard !album.tracks.isEmpty else { return }
                player.playLocalTracks(album.tracks, startingAt: 0, title: album.title)
            },
            playArtist: { artist in
                guard !artist.tracks.isEmpty else { return }
                player.playLocalTracks(artist.tracks, startingAt: 0, title: artist.name)
            },
            playPlaylist: { playlist in
                let tracks = music.tracks(in: playlist.id)
                guard !tracks.isEmpty else { return }
                player.playLocalTracks(tracks, startingAt: 0, title: playlist.name)
            },
            openAlbum: { album in
                path.append(.album(album.id))
            },
            openArtist: { artist in
                path.append(.artist(artist.id))
            },
            openPlaylist: { playlist in
                path.append(.playlist(playlist.id))
            },
            editTrack: { track in
                trackEditor = track
            },
            editAlbumArtwork: { album in
                artworkEditor = MusicArtworkEditor(
                    title: album.title,
                    subtitle: album.artist,
                    currentURL: album.artworkURL,
                    search: { await music.artworkCandidates(for: album) },
                    save: { url in music.setArtwork(url, for: album) }
                )
            },
            editArtistArtwork: { artist in
                artworkEditor = MusicArtworkEditor(
                    title: artist.name,
                    subtitle: artist.details,
                    currentURL: artist.artworkURL,
                    search: { await music.artworkCandidates(for: artist) },
                    save: { url in music.setArtwork(url, for: artist) }
                )
            },
            addToNewPlaylist: { track in
                playlistPrompt = PlaylistPromptRequest(
                    mode: .create(trackIDs: [track.id]),
                    initialName: ""
                )
            },
            addTracksToPlaylist: { playlist in
                trackPickerPlaylist = playlist
            },
            removeFromPlaylist: { track, playlist in
                music.removeTrack(track.id, from: playlist.id)
            },
            deleteTrack: { track in
                pendingDelete = track
            },
            createPlaylist: {
                playlistPrompt = PlaylistPromptRequest(mode: .create(trackIDs: []), initialName: "")
            },
            renamePlaylist: { playlist in
                playlistPrompt = PlaylistPromptRequest(
                    mode: .rename(playlist),
                    initialName: playlist.name
                )
            },
            deletePlaylist: { playlist in
                pendingPlaylistDelete = playlist
            }
        )
    }

    private func delete(_ track: LocalTrack) {
        if player.localTrack?.id == track.id {
            player.stop()
        }
        music.removeTrack(id: track.id)
    }

    private var allVisibleSelected: Bool {
        !visibleTracks.isEmpty
            && visibleTracks.allSatisfy { selectedTrackIDs.contains($0.id) }
    }

    private func beginSelection() {
        selectedTrackIDs.removeAll()
        isSelecting = true
    }

    private func exitSelection() {
        isSelecting = false
        selectedTrackIDs.removeAll()
    }

    private func toggleSelection(_ track: LocalTrack) {
        if selectedTrackIDs.contains(track.id) {
            selectedTrackIDs.remove(track.id)
        } else {
            selectedTrackIDs.insert(track.id)
        }
    }

    private func toggleSelectAll() {
        let ids = Set(visibleTracks.map(\.id))
        if allVisibleSelected {
            selectedTrackIDs.subtract(ids)
        } else {
            selectedTrackIDs.formUnion(ids)
        }
    }

    private func deleteSelectedTracks() {
        let ids = selectedTrackIDs
        if let current = player.localTrack, ids.contains(current.id) {
            player.stop()
        }
        music.removeTracks(ids: ids)
        exitSelection()
    }

    private func trackWord(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if (11...14).contains(mod100) { return "треков" }
        switch mod10 {
        case 1: return "трек"
        case 2, 3, 4: return "трека"
        default: return "треков"
        }
    }

    private func delete(_ playlist: MusicPlaylist) {
        music.deletePlaylist(id: playlist.id)
        path.removeAll { $0 == .playlist(playlist.id) }
    }

    // MARK: - Import

    private var importTypes: [UTType] {
        var types: [UTType] = [.audio, .folder]
        for ext in MusicPlaylistFile.fileExtensions {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertText = error.localizedDescription

        case .success(let urls):
            guard !urls.isEmpty else { return }

            let playlistExtensions = Set(MusicPlaylistFile.fileExtensions)
            let playlists = urls.filter { playlistExtensions.contains($0.pathExtension.lowercased()) }
            let audio = urls.filter { !playlistExtensions.contains($0.pathExtension.lowercased()) }

            isCopying = true
            Task {
                var parts: [String] = []

                if !audio.isEmpty {
                    let summary = await music.addFiles(audio)
                    parts.append(importSummary(summary))
                }

                for url in playlists {
                    do {
                        let imported = try await music.importPlaylist(from: url)
                        parts.append("Плейлист «\(imported.name)»: \(imported.addedTracks) треков.")
                    } catch {
                        parts.append(error.localizedDescription)
                    }
                }

                isCopying = false
                alertText = parts.joined(separator: "\n\n")
            }
        }
    }

    private func importSharedFiles() {
        isCopying = true
        Task {
            let result = await music.importSharedFolder()
            isCopying = false

            var parts = [importSummary(result.summary)]
            if !result.playlists.isEmpty {
                parts.append("Плейлисты:\n" + result.playlists.joined(separator: "\n"))
            }
            alertText = parts.joined(separator: "\n\n")
        }
    }

    private func importSummary(_ summary: MusicImportSummary) -> String {
        var parts: [String] = []
        if summary.added > 0 {
            parts.append("Добавлено: \(summary.added)")
        }
        if summary.skipped > 0 {
            parts.append("Пропущено: \(summary.skipped)")
        }
        if summary.missing > 0 {
            parts.append("Не найдено: \(summary.missing)")
        }
        if parts.isEmpty {
            parts.append("Новых треков не появилось.")
        }
        if let firstError = summary.errors.first {
            parts.append(firstError)
        }
        return parts.joined(separator: "\n")
    }
}
