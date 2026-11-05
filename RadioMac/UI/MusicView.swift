import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Local music page: library navigation on the left, albums, artists,
/// playlists or the track table on the right, and the shared transport bar.
struct MusicView: View {
    @ObservedObject var model: MusicViewModel
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: RadioPlayerService
    @ObservedObject var equalizer: EqualizerService
    @ObservedObject var sleepTimer: SleepTimerService
    @ObservedObject var toasts: ToastCenter

    let onBack: () -> Void
    let onClose: () -> Void
    let onOpenEqualizer: () -> Void

    @Environment(\.palette) var palette
    @FocusState var searchFocused: Bool

    @State var showSources = false
    @State var isTargeted = false
    @State var pendingDeleteTrack: LocalTrack?
    @State var pendingDeletePlaylist: MusicPlaylist?
    @State var artworkEditor: MusicArtworkEditor?

    @State var albums: [MusicAlbum] = []
    @State var artists: [MusicArtist] = []

    /// Cached so the 0.4 s playback tick does not re-sort a big library.
    @State var visibleSections: [MusicTrackSection] = []
    /// Flattened sections in display order — the queue the player receives.
    @State var visibleTracks: [LocalTrack] = []

    // MARK: - Derived

    var searchNeedle: String {
        model.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
    }

    var selectedPlaylist: MusicPlaylist? {
        model.selectedPlaylistID.flatMap { library.playlist(id: $0) }
    }

    var selectedAlbum: MusicAlbum? {
        model.selectedAlbumID.flatMap { id in albums.first { $0.id == id } }
    }

    var selectedArtist: MusicArtist? {
        model.selectedArtistID.flatMap { id in artists.first { $0.id == id } }
    }

    var filteredAlbums: [MusicAlbum] {
        guard !searchNeedle.isEmpty else { return albums }
        return albums.filter { $0.searchText.contains(searchNeedle) }
    }

    var filteredArtists: [MusicArtist] {
        guard !searchNeedle.isEmpty else { return artists }
        return artists.filter { $0.searchText.contains(searchNeedle) }
    }

    var filteredPlaylists: [MusicPlaylist] {
        guard !searchNeedle.isEmpty else { return library.playlists }
        return library.playlists.filter {
            $0.name
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .lowercased()
                .contains(searchNeedle)
        }
    }

    var tracksSubtitle: String {
        guard !visibleTracks.isEmpty else { return "Локальные файлы и плейлисты" }
        return "\(MusicCount.tracks(visibleTracks.count)) · \(LocalTrack.totalDurationText(visibleTracks))"
    }

    var queueTitle: String {
        selectedPlaylist?.name ?? "Все треки"
    }

    func recomputeAll() {
        recomputeCollections()
        recomputeVisibleTracks()
    }

    func recomputeCollections() {
        albums = library.albums
        artists = library.artists
        if let id = model.selectedAlbumID, !albums.contains(where: { $0.id == id }) {
            model.selectedAlbumID = nil
        }
        if let id = model.selectedArtistID, !artists.contains(where: { $0.id == id }) {
            model.selectedArtistID = nil
        }
        if let id = model.selectedPlaylistID, library.playlist(id: id) == nil {
            model.selectedPlaylistID = nil
        }
    }

    func recomputeVisibleTracks() {
        visibleSections = library.sections(
            query: model.searchText,
            playlistID: selectedPlaylist?.id,
            sort: model.sort,
            grouping: model.grouping
        )
        visibleTracks = visibleSections.flatMap(\.tracks)
    }

    // MARK: - Header

    var header: some View {
        PanelHeader(onBack: onBack) {
            HStack(spacing: Space.s) {
                if library.isScanning || library.isEnriching {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .accessibilityLabel(library.scanStatus ?? "Идёт обработка")
                }

                PanelMenu {
                    Button("Добавить папку…") { chooseFolder() }
                    Button("Добавить файлы…") { chooseFiles() }
                    Divider()
                    Button("Новый плейлист…") { model.presentCreatePlaylist() }
                    Button("Импорт M3U…") { importPlaylist() }
                    Button("Экспорт плейлиста в M3U…") { exportPlaylist() }
                        .disabled(selectedPlaylist == nil)
                    Divider()
                    Button("Пересканировать папки") { library.rescan() }
                    Button(library.isEnriching ? "Обогащение идёт…" : "Обогатить из сети") {
                        library.startEnrichment()
                    }
                    .disabled(library.isEnriching)
                    Divider()
                    Button("Источники и папки…") { showSources = true }
                }

                CircleIconButton(
                    systemName: "xmark",
                    size: 11,
                    help: "Скрыть окно",
                    action: onClose
                )
            }
        }
    }

    // MARK: - Content

    var content: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            sidebar
            pageColumn
        }
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.s)
        .frame(maxHeight: .infinity)
    }

    var pageColumn: some View {
        Group {
            if let album = selectedAlbum {
                albumPage(album)
            } else if let artist = selectedArtist {
                artistPage(artist)
            } else if let playlist = selectedPlaylist {
                playlistPage(playlist)
            } else {
                switch model.page {
                case .allTracks:
                    tracksPage(
                        title: "Все треки",
                        subtitle: tracksSubtitle,
                        backTitle: nil,
                        back: nil,
                        prompt: "Поиск треков"
                    )
                case .albums:
                    albumsPage
                case .artists:
                    artistsPage
                case .playlists:
                    playlistsPage
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sidebar

    func tracksPage(
        title: String,
        subtitle: String,
        backTitle: String?,
        back: (() -> Void)?,
        prompt: String
    ) -> some View {
        VStack(spacing: 0) {
            headingRow(title: title, subtitle: subtitle, backTitle: backTitle, back: back)

            HStack(alignment: .bottom, spacing: Space.m) {
                searchLine(prompt: prompt)
                sortMenu
                groupingMenu
            }
            .padding(.top, Space.l)

            columnHeader
                .padding(.top, Space.m)
                .padding(.bottom, Space.xs)

            trackTable
            footer
        }
    }

    func headingRow(
        title: String,
        subtitle: String,
        backTitle: String?,
        back: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let backTitle, let back {
                    TextButton(title: backTitle, systemImage: "arrow.left", action: back)
                }
                PageHeading(
                    title: LocalizedStringKey(title),
                    subtitle: LocalizedStringKey(subtitle)
                )
            }
            Spacer()
            actionsMenu
        }
    }

    func searchLine(prompt: String) -> some View {
        SearchLine(
            text: $model.searchText,
            isFocused: $searchFocused,
            prompt: LocalizedStringKey(prompt),
            accessibilityLabel: prompt
        )
    }

    func detailToolbar(backTitle: String, back: @escaping () -> Void) -> some View {
        HStack(spacing: Space.m) {
            TextButton(title: backTitle, systemImage: "arrow.left", action: back)
            Spacer()
            actionsMenu
        }
    }

    var actionsMenu: some View {
        Menu {
            Button("Добавить папку…") { chooseFolder() }
            Button("Добавить файлы…") { chooseFiles() }
            Divider()
            Button("Новый плейлист…") { model.presentCreatePlaylist() }
            Button("Импорт M3U…") { importPlaylist() }
            Button("Экспорт в M3U…") { exportPlaylist() }
                .disabled(selectedPlaylist == nil)
            if let playlist = selectedPlaylist {
                Divider()
                Button("Переименовать «\(playlist.name)»…") { model.presentRename(playlist) }
                Button(role: .destructive) {
                    pendingDeletePlaylist = playlist
                } label: {
                    Text("Удалить плейлист")
                }
            }
            Divider()
            Button("Обогатить из сети") { library.startEnrichment() }
                .disabled(library.isEnriching)
            Button("Источники…") { showSources = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .medium))
                Text("Действия")
                    .font(Typeface.captionMedium)
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.m)
            .frame(height: 30)
            .overlay(Rectangle().strokeBorder(palette.separatorStrong, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Действия с локальной музыкой")
    }

    /// Compact sort picker: custom order or one of the metadata orders.
    var sortMenu: some View {
        Menu {
            ForEach(MusicSortOrder.allCases) { option in
                Button {
                    model.sort = option
                } label: {
                    if option == model.sort {
                        Label(LocalizedStringKey(option.title), systemImage: "checkmark")
                    } else {
                        Text(LocalizedStringKey(option.title))
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 30, height: 30)
                .overlay(Rectangle().strokeBorder(palette.separatorStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Сортировка: \(model.sort.title)")
        .accessibilityLabel("Сортировка")
        .accessibilityValue(Text(LocalizedStringKey(model.sort.title)))
    }

    /// Compact picker above the table: flat list, by artist, by album or by genre.
    var groupingMenu: some View {
        Menu {
            ForEach(MusicGrouping.allCases) { option in
                Button {
                    model.grouping = option
                } label: {
                    if option == model.grouping {
                        Label(LocalizedStringKey(option.title), systemImage: "checkmark")
                    } else {
                        Text(LocalizedStringKey(option.title))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 10, weight: .medium))
                Text(LocalizedStringKey(model.grouping.shortTitle))
                    .font(Typeface.captionMedium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(model.grouping == .none ? palette.textPrimary : palette.accent)
            .padding(.horizontal, Space.m)
            .frame(height: 30)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        model.grouping == .none
                            ? palette.separatorStrong
                            : palette.accent.opacity(0.55),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Группировка треков")
        .accessibilityLabel("Группировка треков")
        .accessibilityValue(Text(LocalizedStringKey(model.grouping.title)))
    }

    var columnHeader: some View {
        HStack(spacing: Space.s) {
            Color.clear.frame(width: 10, height: 10)
            Color.clear.frame(width: 30, height: 10)
            Text("ТРЕК").frame(maxWidth: .infinity, alignment: .leading)
            Text("АЛЬБОМ").frame(width: 138, alignment: .leading)
            Text("ВРЕМЯ").frame(width: 42, alignment: .trailing)
            Color.clear.frame(width: 24 + Space.scrollLane, height: 10)
        }
        .font(Typeface.overline)
        .tracking(1.2)
        .foregroundStyle(palette.textSecondary)
    }

    @ViewBuilder
    var trackTable: some View {
        if visibleTracks.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(
                    spacing: 0,
                    pinnedViews: model.grouping == .none ? [] : [.sectionHeaders]
                ) {
                    ForEach(visibleSections) { section in
                        Section {
                            ForEach(section.tracks) { track in
                                reorderableTrackRow(track)
                            }
                        } header: {
                            if model.grouping != .none {
                                sectionHeader(section)
                            }
                        }
                    }

                    if canReorderTracks {
                        Color.clear
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                handleTrackDrop(providers) { id in
                                    moveTrackToEnd(id)
                                }
                            }
                    }
                }
                .padding(.bottom, Space.s)
            }
            .scrollIndicators(.automatic)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Список треков")
            .accessibilityIdentifier("music-track-list")
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.95),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    var trackPageActions: MusicTrackActions {
        makeTrackActions(
            queue: visibleTracks,
            title: queueTitle,
            isInPlaylist: selectedPlaylist != nil
        )
    }

    /// Sticky header of a group: name, extra context, totals and "play group".
    func sectionHeader(_ section: MusicTrackSection) -> some View {
        HStack(alignment: .center, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(section.title))
                    .font(Typeface.section)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = section.subtitle {
                    Text(subtitle)
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Space.s)

            Text(sectionSummary(section))
                .font(Typeface.monoSmall)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)

            CircleIconButton(
                systemName: "play.fill",
                size: 9,
                help: "Играть группу «\(section.title)»"
            ) {
                play(section)
            }
        }
        .padding(.top, Space.s)
        .padding(.bottom, Space.s)
        .background(palette.surface)
        .overlay(alignment: .bottom) { Hairline() }
        .zIndex(1)
    }

    func sectionSummary(_ section: MusicTrackSection) -> String {
        "\(MusicCount.tracks(section.tracks.count)) · \(LocalTrack.totalDurationText(section.tracks))"
    }

    var footer: some View {
        HStack(spacing: Space.m) {
            if canReorderTracks {
                Text("Перетащите строки, чтобы изменить порядок")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(
                    library.missingCount > 0
                        ? "Не найдено файлов: \(library.missingCount)"
                        : "Плейлисты хранят ссылки на файлы — музыка не копируется"
                )
                .font(Typeface.caption)
                .foregroundStyle(library.missingCount > 0 ? palette.red : palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer()

            if library.isEnriching {
                Text(library.enrichmentStatus ?? "Обогащение…")
                    .font(Typeface.monoSmall)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                TextButton(title: "Остановить") { library.cancelEnrichment() }
            } else {
                TextButton(title: "Обогатить из сети", systemImage: "sparkles") {
                    library.startEnrichment()
                }
            }

            if let playlist = selectedPlaylist {
                TextButton(title: "M3U", systemImage: "square.and.arrow.up") {
                    exportPlaylist(playlist)
                }
                .help("Экспортировать «\(playlist.name)» в M3U")
            }
        }
        .padding(.top, Space.xs)
    }

    // MARK: - Album, artist and playlist pages

    func makeTrackActions(
        queue: [LocalTrack],
        title: String,
        isInPlaylist: Bool
    ) -> MusicTrackActions {
        MusicTrackActions(
            isCurrent: { player.localTrack?.id == $0.id },
            isPlaying: { player.localTrack?.id == $0.id && player.isPlaying },
            isLoading: { player.localTrack?.id == $0.id && player.status == .loading },
            isInPlaylist: isInPlaylist,
            playlists: library.playlists,
            onPlay: { play($0, queue: queue, title: title) },
            onEnrich: { enrich($0) },
            onEdit: { model.editor = $0 },
            onAddToPlaylist: { track, playlist in
                library.addTracks([track.id], to: playlist.id)
                toasts.show("Добавлено в «\(playlist.name)»", kind: .success)
            },
            onRemoveFromPlaylist: { track in
                if let playlist = selectedPlaylist {
                    library.removeTrack(track.id, from: playlist.id)
                }
            },
            onRevealInFinder: { library.revealInFinder($0) },
            onDelete: { pendingDeleteTrack = $0 }
        )
    }

    func playableTracks(_ tracks: [LocalTrack]) -> [LocalTrack] {
        tracks.filter { !$0.isMissing }
    }

    // MARK: - Empty state

    func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typeface.overline)
            .tracking(1.1)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Player bar

    /// The queue the transport bar starts when nothing is playing yet: the
    /// opened album or artist, otherwise the visible track list.
    var fallbackQueue: [LocalTrack] {
        if let album = selectedAlbum { return playableTracks(album.tracks) }
        if let artist = selectedArtist { return playableTracks(artist.tracks) }
        return visibleTracks
    }

    var fallbackTitle: String {
        if let album = selectedAlbum { return album.title }
        if let artist = selectedArtist { return artist.name }
        return queueTitle
    }

    var playerBar: some View {
        PlayerBar(
            player: player,
            equalizer: equalizer,
            sleepTimer: sleepTimer,
            onOpenEqualizer: onOpenEqualizer,
            onPrevious: { player.playPreviousLocalTrack() },
            onNext: { player.playNextLocalTrack() },
            canPrevious: player.isLocalPlayback && player.canPlayPreviousLocalTrack,
            canNext: player.isLocalPlayback && player.canPlayNextLocalTrack,
            canPlay: !fallbackQueue.isEmpty || player.isLocalPlayback
                || player.station != nil || player.isActive,
            onPlayFallback: {
                guard !fallbackQueue.isEmpty else { return }
                player.playLocalTracks(fallbackQueue, startingAt: 0, title: fallbackTitle)
            }
        )
    }

    // MARK: - Actions

    func play(_ track: LocalTrack, queue: [LocalTrack], title: String) {
        if track.isMissing {
            toasts.show("Файл не найден: \(track.fileName)", kind: .error)
            return
        }
        let playable = playableTracks(queue)
        guard let index = playable.firstIndex(where: { $0.id == track.id }) else { return }
        player.playLocalTracks(playable, startingAt: index, title: title)
    }

    func playAlbum(_ album: MusicAlbum) {
        let playable = playableTracks(album.tracks)
        guard !playable.isEmpty else {
            toasts.show("В альбоме нет доступных файлов", kind: .info)
            return
        }
        player.playLocalTracks(playable, startingAt: 0, title: album.title)
    }

    func playArtist(_ artist: MusicArtist) {
        let playable = playableTracks(artist.tracks)
        guard !playable.isEmpty else {
            toasts.show("У исполнителя нет доступных файлов", kind: .info)
            return
        }
        player.playLocalTracks(playable, startingAt: 0, title: artist.name)
    }

    func playPlaylist(_ playlist: MusicPlaylist) {
        let items = library.sections(
            query: "",
            playlistID: playlist.id,
            sort: model.sort,
            grouping: model.grouping
        )
        .flatMap(\.tracks)
        .filter { !$0.isMissing }
        guard !items.isEmpty else {
            toasts.show("Плейлист пуст", kind: .info)
            return
        }
        player.playLocalTracks(items, startingAt: 0, title: playlist.name)
    }

    func play(_ section: MusicTrackSection) {
        let playable = playableTracks(section.tracks)
        guard !playable.isEmpty else {
            toasts.show("В группе нет доступных файлов", kind: .info)
            return
        }
        let title = section.subtitle.map { "\($0) — \(section.title)" } ?? section.title
        player.playLocalTracks(playable, startingAt: 0, title: title)
    }

    func enrich(_ track: LocalTrack) {
        Task { @MainActor in
            if let match = await library.enrich(trackID: track.id) {
                toasts.show(
                    "«\(track.displayTitle)»: \(match.summary)",
                    kind: .success
                )
            } else {
                toasts.show("Ничего не нашлось в сети", kind: .info)
            }
        }
    }

    func presentArtworkEditor(for album: MusicAlbum) {
        artworkEditor = MusicArtworkEditor(
            title: "Обложка альбома",
            subtitle: album.artist.map { "\(album.title) — \($0)" } ?? album.title,
            note: "Обложка применится ко всем трекам альбома; аудиофайлы не изменяются.",
            currentURL: album.artworkURL,
            search: { await library.artworkCandidates(for: album) },
            save: { url in
                library.setArtwork(url, for: album)
                toasts.show(
                    url == nil ? "Обложка альбома убрана" : "Обложка альбома обновлена",
                    kind: .success
                )
            }
        )
    }

    func presentArtworkEditor(for artist: MusicArtist) {
        artworkEditor = MusicArtworkEditor(
            title: "Обложка исполнителя",
            subtitle: artist.details,
            note: "Обложка исполнителя хранится отдельно и не заменяет обложки альбомов.",
            currentURL: artist.artworkURL,
            search: { await library.artworkCandidates(for: artist) },
            save: { url in
                library.setArtwork(url, for: artist)
                toasts.show(
                    url == nil ? "Обложка исполнителя убрана" : "Обложка исполнителя обновлена",
                    kind: .success
                )
            }
        )
    }

    func submit(_ prompt: MusicPlaylistPrompt, name: String) {
        switch prompt.mode {
        case .create:
            guard let playlist = library.createPlaylist(name: name) else { return }
            model.openPlaylist(playlist.id)
            toasts.show("Плейлист «\(playlist.name)» создан", kind: .success)
        case .rename(let playlist):
            library.renamePlaylist(id: playlist.id, name: name)
            toasts.show("Плейлист переименован", kind: .success)
        }
        model.prompt = nil
    }

    // MARK: - Files

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"
        panel.message = "Выберите папки с музыкой"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { @MainActor in
            var added = 0
            for url in urls {
                let summary = await library.addFolder(url)
                added += summary.added
            }
            library.flush()
            toasts.show(
                added > 0 ? "Добавлено треков: \(added)" : "Новых аудиофайлов не найдено",
                kind: added > 0 ? .success : .info
            )
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { @MainActor in
            let summary = await library.addFiles(urls)
            library.flush()
            toasts.show(
                summary.added > 0
                    ? "Добавлено треков: \(summary.added)"
                    : "Файлы не добавлены",
                kind: summary.added > 0 ? .success : .info
            )
        }
    }

    func handleDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let playlists = urls.filter { LocalAudioMetadata.isPlaylistFile($0) }
        let audio = urls.filter { !LocalAudioMetadata.isPlaylistFile($0) }
        Task { @MainActor in
            if !audio.isEmpty {
                let summary = await library.addFiles(audio)
                if summary.added > 0 {
                    toasts.show("Добавлено треков: \(summary.added)", kind: .success)
                } else if !summary.errors.isEmpty {
                    toasts.show(summary.errors.first ?? "Не удалось добавить файлы", kind: .error)
                }
            }
            for url in playlists {
                await runImport(url)
            }
            library.flush()
        }
        return true
    }

    func importPlaylist() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.playlistTypes
        panel.prompt = "Импортировать"
        panel.message = "Выберите M3U-плейлист"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            await runImport(url)
        }
    }

    static var playlistTypes: [UTType] {
        [UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8")]
            .compactMap { $0 }
    }

    /// M3U files usually reference tracks next to them; sandboxed apps need a
    /// separate grant for that folder, so the user picks it once.
    func runImport(_ url: URL) async {
        let folder = url.deletingLastPathComponent()
        if !library.hasAccess(toFolder: folder) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.prompt = "Разрешить"
            panel.message = "Разрешите доступ к папке «\(folder.lastPathComponent)», чтобы открыть файлы плейлиста."
            if panel.runModal() == .OK, let granted = panel.url {
                library.grantFolderAccess(granted)
            }
        }

        do {
            let result = try await library.importPlaylist(from: url)
            model.openPlaylist(result.playlistID)
            var text = "Плейлист «\(result.name)»: \(result.addedTracks) новых треков"
            if result.skippedEntries > 0 {
                text += ", пропущено \(result.skippedEntries)"
            }
            toasts.show(text, kind: .success)
        } catch {
            toasts.show(error.localizedDescription, kind: .error)
        }
    }

    func exportPlaylist(_ playlist: MusicPlaylist? = nil) {
        guard let playlist = playlist ?? selectedPlaylist,
              let data = library.m3uData(for: playlist.id)
        else {
            toasts.show("Сначала выберите плейлист", kind: .info)
            return
        }
        let panel = NSSavePanel()
        let safeName = playlist.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(safeName).m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            toasts.show("Экспортировано: \(url.lastPathComponent)", kind: .success)
        } catch {
            toasts.show("Не удалось сохранить: \(error.localizedDescription)", kind: .error)
        }
    }
}
