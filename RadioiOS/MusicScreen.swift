// swiftlint:disable file_length
import MediaPlayer
import SwiftUI
import UIKit
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
    @State private var mediaProgress: String?
    @State private var mediaNotice: String?
    @State private var mediaPermissionDenied = false
    @State private var mediaTask: Task<Void, Never>?
    @State private var pendingAllMedia: [MPMediaItem] = []
    @State private var pendingAllExisting = 0
    @State private var pendingAllUnavailable = 0
    @State private var pendingAllPlaylists = 0
    @State private var showImportAllMedia = false

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

                if let mediaNotice {
                    mediaNoticeBar(mediaNotice)
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
        .task(id: router.importMediaPlaylists) {
            guard router.importMediaPlaylists else { return }
            router.importMediaPlaylists = false
            requestMediaPlaylists()
        }
        .task(id: router.importAllMediaLibrary) {
            guard router.importAllMediaLibrary else { return }
            router.importAllMediaLibrary = false
            requestAllMediaLibrary()
        }
        .task(id: router.importMediaLibrary) {
            guard router.importMediaLibrary else { return }
            router.importMediaLibrary = false
            requestMediaLibrary()
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
            if mediaPermissionDenied {
                Button("Настройки") { openAppSettings() }
            }
            Button("OK", role: .cancel) {
                alertText = nil
                mediaPermissionDenied = false
            }
        } message: {
            Text(alertText ?? "")
        }
        .confirmationDialog(
            "Импортировать всю медиатеку?",
            isPresented: $showImportAllMedia,
            titleVisibility: .visible
        ) {
            Button("Импортировать") {
                let items = pendingAllMedia
                pendingAllMedia = []
                importMediaItems(items, importPlaylists: true)
            }
            Button("Отмена", role: .cancel) {
                pendingAllMedia = []
            }
        } message: {
            Text(allMediaConfirmationText)
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

    private func mediaNoticeBar(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(palette.green)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.s)

            Button {
                mediaNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Скрыть сообщение")
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(palette.surfaceRaised)
        .overlay(alignment: .bottom) { Hairline() }
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
                Label("Импортировать из «Файлов»…", systemImage: "square.and.arrow.down")
            }

            Button {
                requestMediaLibrary()
            } label: {
                Label("Импортировать из медиатеки…", systemImage: "music.note")
            }

            Button {
                requestAllMediaLibrary()
            } label: {
                Label("Импортировать всю медиатеку…", systemImage: "music.note.list")
            }

            Button {
                requestMediaPlaylists()
            } label: {
                Label("Импортировать плейлисты медиатеки…", systemImage: "music.note.list")
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

            if mediaTask != nil {
                Button("Отменить") {
                    mediaTask?.cancel()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.red)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(palette.surfaceRaised)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var progressText: String {
        if let mediaProgress { return mediaProgress }
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

    private func requestMediaLibrary() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            presentMediaPicker()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized {
                        presentMediaPicker()
                    } else {
                        presentMediaPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            presentMediaPermissionDenied()
        @unknown default:
            presentMediaPermissionDenied()
        }
    }

    private func requestAllMediaLibrary() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            prepareImportAllMedia()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized {
                        prepareImportAllMedia()
                    } else {
                        presentMediaPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            presentMediaPermissionDenied()
        @unknown default:
            presentMediaPermissionDenied()
        }
    }

    private func prepareImportAllMedia() {
        let all = MPMediaQuery.songs().items ?? []
        let available = all.filter {
            !$0.isCloudItem && !$0.hasProtectedAsset && $0.assetURL != nil
        }
        let fresh = available.filter { existingTrack(for: $0) == nil }
        let mediaPlaylists = allMediaPlaylists()

        pendingAllExisting = available.count - fresh.count
        pendingAllUnavailable = all.count - available.count
        pendingAllPlaylists = mediaPlaylists.count

        guard !fresh.isEmpty || !mediaPlaylists.isEmpty else {
            mediaNotice = all.isEmpty
                ? "В медиатеке нет песен и плейлистов."
                : "Все доступные песни уже в библиотеке, плейлистов нет."
            return
        }

        pendingAllMedia = fresh
        showImportAllMedia = true
    }

    private var allMediaConfirmationText: String {
        var lines: [String] = []
        if pendingAllMedia.isEmpty {
            lines.append("Новых песен нет — импортирую только плейлисты.")
        } else {
            lines.append("Будет добавлено песен: \(pendingAllMedia.count).")
        }
        if pendingAllExisting > 0 {
            lines.append("Уже в библиотеке: \(pendingAllExisting).")
        }
        if pendingAllUnavailable > 0 {
            lines.append("Недоступно (облако или DRM): \(pendingAllUnavailable).")
        }
        if pendingAllPlaylists > 0 {
            lines.append("Плейлистов из медиатеки: \(pendingAllPlaylists).")
        }
        lines.append("Импорт может занять несколько минут, его можно отменить.")
        return lines.joined(separator: "\n")
    }

    private func allMediaPlaylists() -> [MPMediaPlaylist] {
        (MPMediaQuery.playlists().collections ?? []).compactMap { $0 as? MPMediaPlaylist }
    }

    private func existingTrack(for item: MPMediaItem) -> LocalTrack? {
        let persistentID = String(item.persistentID)
        if let track = music.tracks.first(where: { $0.mediaLibraryID == persistentID }) {
            return track
        }

        // Tracks imported before the persistent ID was stored are matched by
        // title, artist and duration so a repeated import does not duplicate them.
        guard let title = LocalTrack.trimmed(item.title)?.lowercased() else {
            return nil
        }
        let artist = LocalTrack.trimmed(item.artist)?.lowercased() ?? ""
        let duration = item.playbackDuration

        return music.tracks.first { track in
            guard track.title.lowercased() == title,
                  (track.artist?.lowercased() ?? "") == artist
            else { return false }
            return duration <= 0 || abs((track.duration ?? 0) - duration) < 2
        }
    }

    private func isMediaItemAlreadyImported(_ item: MPMediaItem) -> Bool {
        existingTrack(for: item) != nil
    }

    private func requestMediaPlaylists() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            importPlaylistsOnly()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized {
                        importPlaylistsOnly()
                    } else {
                        presentMediaPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            presentMediaPermissionDenied()
        @unknown default:
            presentMediaPermissionDenied()
        }
    }

    private func importPlaylistsOnly() {
        guard mediaTask == nil else { return }
        mediaNotice = nil
        isCopying = true

        mediaTask = Task {
            mediaProgress = "Импортирую плейлисты медиатеки…"
            let result = importMediaPlaylists(mapping: [:])
            mediaProgress = nil
            isCopying = false
            mediaTask = nil
            mediaNotice = playlistSummary(
                imported: result.playlists,
                tracks: result.tracks
            )
        }
    }

    private func presentMediaPicker() {
        MediaLibraryPresenter.shared.present {
            importMediaItems($0)
        } onCancel: {
        }
    }

    private func presentMediaPermissionDenied() {
        mediaPermissionDenied = true
        alertText = "Доступ к медиатеке запрещён. Разрешите его в Настройки → RadioMac → Медиатека."
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        alertText = nil
        mediaPermissionDenied = false
    }

    private func importMediaItems(_ items: [MPMediaItem], importPlaylists: Bool = false) {
        guard !items.isEmpty || importPlaylists, mediaTask == nil else { return }
        mediaNotice = nil
        isCopying = true

        mediaTask = Task {
            var added = 0
            var already = 0
            var skipped: [String] = []
            var cancelled = false
            var mapping: [String: String] = [:]

            for (index, item) in items.enumerated() {
                if Task.isCancelled {
                    cancelled = true
                    break
                }

                mediaProgress = "Импортирую из медиатеки: \(index + 1) из \(items.count)"

                if let track = existingTrack(for: item) {
                    already += 1
                    mapping[String(item.persistentID)] = track.id
                    continue
                }

                guard let temporary = await MediaLibraryExporter.export(item) else {
                    if Task.isCancelled {
                        cancelled = true
                        break
                    }
                    skipped.append(mediaTitle(item))
                    continue
                }

                let summary = await music.addFiles([temporary])
                if summary.added > 0 {
                    added += summary.added
                    if let trackID = applyMetadata(
                        from: item,
                        toTrackWithFileName: temporary.lastPathComponent
                    ) {
                        mapping[String(item.persistentID)] = trackID
                    } else if let track = existingTrack(for: item) {
                        mapping[String(item.persistentID)] = track.id
                        assignMediaID(to: track, from: item)
                    }
                } else if let track = existingTrack(for: item) {
                    mapping[String(item.persistentID)] = track.id
                    assignMediaID(to: track, from: item)
                } else {
                    skipped.append(mediaTitle(item))
                }
                try? FileManager.default.removeItem(at: temporary)
            }

            var playlistCount = 0
            var playlistTracks = 0
            if importPlaylists, !cancelled {
                mediaProgress = "Импортирую плейлисты медиатеки…"
                let result = importMediaPlaylists(mapping: mapping)
                playlistCount = result.playlists
                playlistTracks = result.tracks
            }

            mediaProgress = nil
            isCopying = false
            mediaTask = nil
            mediaNotice = mediaSummary(
                added: added,
                already: already,
                skipped: skipped,
                cancelled: cancelled,
                playlists: playlistCount,
                playlistTracks: playlistTracks
            )
        }
    }

    @discardableResult
    private func applyMetadata(from item: MPMediaItem, toTrackWithFileName fileName: String) -> String? {
        guard let track = music.tracks.first(where: {
            ($0.path as NSString).lastPathComponent == fileName
        }) else { return nil }

        var updated = track
        if let title = LocalTrack.trimmed(item.title) {
            updated.title = title
        }
        if let artist = LocalTrack.trimmed(item.artist) {
            updated.artist = artist
        }
        if let album = LocalTrack.trimmed(item.albumTitle) {
            updated.album = album
        }
        if let genre = LocalTrack.trimmed(item.genre) {
            updated.genre = genre
        }
        if item.albumTrackNumber > 0 {
            updated.trackNumber = Int(item.albumTrackNumber)
        }
        if item.playbackDuration > 0 {
            updated.duration = item.playbackDuration
        }
        updated.mediaLibraryID = String(item.persistentID)
        if let image = item.artwork?.image(at: CGSize(width: 600, height: 600)),
           let data = image.jpegData(compressionQuality: 0.9),
           let stored = MusicArtworkStore.save(data, for: "media-\(UUID().uuidString)") {
            updated.artworkURL = stored
        }
        music.update(updated)
        return updated.id
    }

    private func assignMediaID(to track: LocalTrack, from item: MPMediaItem) {
        guard track.mediaLibraryID == nil else { return }
        var updated = track
        updated.mediaLibraryID = String(item.persistentID)
        music.update(updated)
    }

    private func importMediaPlaylists(mapping: [String: String]) -> (playlists: Int, tracks: Int) {
        let mediaPlaylists = allMediaPlaylists()
        var importedPlaylists = 0
        var importedTracks = 0

        for mediaPlaylist in mediaPlaylists {
            guard let rawName = mediaPlaylist.value(
                forProperty: MPMediaPlaylistPropertyName
            ) as? String else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            var seen: Set<String> = []
            let trackIDs: [String] = mediaPlaylist.items.compactMap { item in
                let id = mapping[String(item.persistentID)]
                    ?? existingTrack(for: item)?.id
                guard let id, seen.insert(id).inserted else { return nil }
                return id
            }
            guard !trackIDs.isEmpty else { continue }

            if let existing = music.playlists.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                let before = Set(existing.trackIDs)
                let additions = trackIDs.filter { !before.contains($0) }
                music.addTracks(additions, to: existing.id)
                importedTracks += additions.count
            } else {
                music.createPlaylist(name: name, trackIDs: trackIDs)
                importedTracks += trackIDs.count
            }
            importedPlaylists += 1
        }

        return (importedPlaylists, importedTracks)
    }

    private func mediaTitle(_ item: MPMediaItem) -> String {
        let parts = [item.artist, item.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Без названия" : parts.joined(separator: " — ")
    }

    private func playlistSummary(imported: Int, tracks: Int) -> String {
        guard imported > 0 else {
            return "В медиатеке нет плейлистов с добавленными треками."
        }
        return "Импортировано плейлистов: \(imported), треков: \(tracks)."
    }

    private func mediaSummary(
        added: Int,
        already: Int,
        skipped: [String],
        cancelled: Bool,
        playlists: Int,
        playlistTracks: Int
    ) -> String {
        var lines: [String] = []
        if cancelled {
            lines.append("Импорт остановлен.")
        }
        if added > 0 {
            lines.append("Добавлено из медиатеки: \(added).")
        }
        if already > 0 {
            lines.append("Уже в библиотеке: \(already).")
        }
        if playlists > 0 {
            lines.append("Плейлистов: \(playlists), треков в них: \(playlistTracks).")
        }
        if skipped.isEmpty {
            if added == 0, already == 0, playlists == 0, !cancelled {
                lines.append("Ничего не добавлено.")
            }
        } else {
            lines.append("Пропущено: \(skipped.count).")
            lines.append(skipped.prefix(3).joined(separator: "\n"))
            lines.append("Облачные и защищённые треки Apple Music скопировать нельзя.")
        }
        return lines.joined(separator: "\n")
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

// swiftlint:enable file_length
