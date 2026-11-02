import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Local music page: playlists on the left, the track table on the right and
/// the shared transport bar at the bottom.
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

    @Environment(\.palette) private var palette
    @FocusState private var searchFocused: Bool

    @State private var showSources = false
    @State private var isTargeted = false
    @State private var pendingDeleteTrack: LocalTrack?
    @State private var pendingDeletePlaylist: MusicPlaylist?

    /// Cached so the 0.4 s playback tick does not re-sort a big library.
    @State private var visibleTracks: [LocalTrack] = []

    // MARK: - Derived

    private func recomputeVisibleTracks() {
        visibleTracks = library.filteredTracks(
            query: model.searchText,
            playlistID: model.selectedPlaylistID,
            sort: model.sort
        )
    }

    private var selectedPlaylist: MusicPlaylist? {
        model.selectedPlaylistID.flatMap { library.playlist(id: $0) }
    }

    private var heading: String {
        selectedPlaylist?.name ?? "Музыка"
    }

    private var subtitle: String {
        guard !visibleTracks.isEmpty else { return "Локальные файлы и плейлисты" }
        let count = visibleTracks.count
        return "\(count) \(Self.trackWord(count)) · \(LocalTrack.totalDurationText(visibleTracks))"
    }

    private var queueTitle: String {
        selectedPlaylist?.name ?? "Все треки"
    }

    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                header
                content
                playerBar
            }
            .overlay(alignment: .bottom) {
                ToastOverlay(center: toasts)
            }
        }
        .onChange(of: player.status) { _, newValue in
            guard newValue == .error else { return }
            toasts.show(player.consumeError() ?? "Не удалось открыть файл", kind: .error)
        }
        .onChange(of: model.focusSearchToken) { _, _ in searchFocused = true }
        .onChange(of: model.resignSearchToken) { _, _ in searchFocused = false }
        .onAppear(perform: recomputeVisibleTracks)
        .onChange(of: library.tracks) { _, tracks in
            recomputeVisibleTracks()
            guard let current = player.localTrack,
                  let fresh = tracks.first(where: { $0.id == current.id })
            else { return }
            if fresh != current { player.refreshLocalTrack(fresh) }
        }
        .onChange(of: library.playlists) { _, _ in
            recomputeVisibleTracks()
        }
        .onChange(of: model.searchText) { _, _ in recomputeVisibleTracks() }
        .onChange(of: model.selectedPlaylistID) { _, _ in recomputeVisibleTracks() }
        .onChange(of: model.sort) { _, _ in recomputeVisibleTracks() }
        .onChange(of: library.playlists) { _, playlists in
            if let id = model.selectedPlaylistID,
               !playlists.contains(where: { $0.id == id }) {
                model.selectedPlaylistID = nil
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            _ = handleDrop(urls)
            return true
        } isTargeted: { value in
            isTargeted = value
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.accent, lineWidth: isTargeted ? 2 : 0)
                .padding(10)
                .allowsHitTesting(false)
        )
        .sheet(isPresented: $showSources) {
            MusicSourcesView(library: library, toasts: toasts) {
                showSources = false
            }
        }
        .sheet(item: $model.prompt) { prompt in
            MusicPlaylistPromptView(prompt: prompt) { name in
                submit(prompt, name: name)
            } onCancel: {
                model.prompt = nil
            }
        }
        .sheet(item: $model.editor) { track in
            MusicTrackEditorView(track: track, library: library)
        }
        .alert(
            "Удалить трек?",
            isPresented: Binding(
                get: { pendingDeleteTrack != nil },
                set: { if !$0 { pendingDeleteTrack = nil } }
            ),
            presenting: pendingDeleteTrack
        ) { track in
            Button("Отмена", role: .cancel) { pendingDeleteTrack = nil }
            Button("Удалить", role: .destructive) {
                library.removeTrack(id: track.id)
                toasts.show("«\(track.displayTitle)» удалён из библиотеки", kind: .success)
                pendingDeleteTrack = nil
            }
        } message: { track in
            Text("«\(track.displayTitle)» исчезнет из библиотеки и плейлистов. Файл на диске останется.")
        }
        .alert(
            "Удалить плейлист?",
            isPresented: Binding(
                get: { pendingDeletePlaylist != nil },
                set: { if !$0 { pendingDeletePlaylist = nil } }
            ),
            presenting: pendingDeletePlaylist
        ) { playlist in
            Button("Отмена", role: .cancel) { pendingDeletePlaylist = nil }
            Button("Удалить", role: .destructive) {
                library.deletePlaylist(id: playlist.id)
                if model.selectedPlaylistID == playlist.id { model.selectedPlaylistID = nil }
                toasts.show("Плейлист «\(playlist.name)» удалён", kind: .success)
                pendingDeletePlaylist = nil
            }
        } message: { _ in
            Text("Треки останутся в библиотеке — удалится только список.")
        }
    }

    // MARK: - Header

    private var header: some View {
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

    private var content: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            sidebar
            libraryColumn
        }
        .padding(.horizontal, Space.xxl)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.s)
        .frame(maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            sectionLabel("Библиотека")

            NavItem(
                label: "Все треки",
                isSelected: model.selectedPlaylistID == nil,
                isPlaying: player.isLocalPlayback && player.isPlaying
            ) {
                model.selectedPlaylistID = nil
            }

            sectionLabel("Плейлисты")

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if library.playlists.isEmpty {
                        Text("Пока нет плейлистов")
                            .font(Typeface.caption)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.vertical, Space.xs)
                    }
                    ForEach(library.playlists) { playlist in
                        playlistRow(playlist)
                    }
                }
                .padding(.trailing, Space.s)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: Space.s)

            TextButton(title: "Новый плейлист", systemImage: "plus") {
                model.presentCreatePlaylist()
            }
            TextButton(title: "Импорт M3U", systemImage: "square.and.arrow.down") {
                importPlaylist()
            }
            TextButton(title: "Источники…", systemImage: "folder") {
                showSources = true
            }
        }
        .frame(width: 178)
    }

    private var libraryColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.m) {
                PageHeading(
                    title: LocalizedStringKey(heading),
                    subtitle: LocalizedStringKey(subtitle)
                )
                Spacer()
                actionsMenu
            }

            SearchLine(
                text: $model.searchText,
                isFocused: $searchFocused,
                prompt: "Поиск треков",
                accessibilityLabel: "Поиск треков"
            )
            .padding(.top, Space.l)

            columnHeader
                .padding(.top, Space.m)
                .padding(.bottom, Space.xs)

            trackTable

            footer
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Добавить папку…") { chooseFolder() }
            Button("Добавить файлы…") { chooseFiles() }
            Divider()
            Button("Импорт M3U…") { importPlaylist() }
            Button("Экспорт в M3U…") { exportPlaylist() }
                .disabled(selectedPlaylist == nil)
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

    private var columnHeader: some View {
        HStack(spacing: Space.s) {
            Color.clear.frame(width: 10, height: 10)
            Color.clear.frame(width: 30, height: 10)
            Text("ТРЕК").frame(maxWidth: .infinity, alignment: .leading)
            Text("АЛЬБОМ").frame(width: 138, alignment: .leading)
            Text("ВРЕМЯ").frame(width: 42, alignment: .trailing)
            Color.clear.frame(width: 24, height: 10)
        }
        .font(Typeface.overline)
        .tracking(1.2)
        .foregroundStyle(palette.textSecondary)
    }

    @ViewBuilder
    private var trackTable: some View {
        if visibleTracks.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleTracks) { track in
                        MusicTrackRow(
                            track: track,
                            isCurrent: player.localTrack?.id == track.id,
                            isPlaying: player.localTrack?.id == track.id && player.isPlaying,
                            isLoading: player.localTrack?.id == track.id && player.status == .loading,
                            isInPlaylist: selectedPlaylist != nil,
                            playlists: library.playlists,
                            onPlay: { play(track) },
                            onEnrich: { enrich(track) },
                            onEdit: { model.editor = track },
                            onAddToPlaylist: { playlist in
                                library.addTracks([track.id], to: playlist.id)
                                toasts.show("Добавлено в «\(playlist.name)»", kind: .success)
                            },
                            onRemoveFromPlaylist: {
                                if let playlist = selectedPlaylist {
                                    library.removeTrack(track.id, from: playlist.id)
                                }
                            },
                            onRevealInFinder: { library.revealInFinder(track) },
                            onDelete: { pendingDeleteTrack = track }
                        )
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

    private var footer: some View {
        HStack(spacing: Space.m) {
            Text(
                library.missingCount > 0
                    ? "Не найдено файлов: \(library.missingCount)"
                    : "Плейлисты хранят ссылки на файлы — музыка не копируется"
            )
            .font(Typeface.caption)
            .foregroundStyle(library.missingCount > 0 ? palette.red : palette.textTertiary)
            .lineLimit(1)
            .truncationMode(.tail)

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
                    exportPlaylist()
                }
                .help("Экспортировать «\(playlist.name)» в M3U")
            }
        }
        .padding(.top, Space.xs)
    }

    private var playerBar: some View {
        PlayerBar(
            player: player,
            equalizer: equalizer,
            sleepTimer: sleepTimer,
            onOpenEqualizer: onOpenEqualizer,
            onPrevious: { player.playPreviousLocalTrack() },
            onNext: { player.playNextLocalTrack() },
            canPrevious: player.isLocalPlayback && player.canPlayPreviousLocalTrack,
            canNext: player.isLocalPlayback && player.canPlayNextLocalTrack,
            canPlay: !visibleTracks.isEmpty || player.isLocalPlayback
                || player.station != nil || player.isActive,
            onPlayFallback: {
                guard !visibleTracks.isEmpty else { return }
                player.playLocalTracks(visibleTracks, startingAt: 0, title: queueTitle)
            }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        let searching = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let playlist = selectedPlaylist

        return EmptyStateView(
            systemImage: searching ? "magnifyingglass" : "music.note.list",
            title: searching
                ? "Ничего не найдено"
                : (playlist == nil ? "Добавьте музыку" : "Плейлист пуст"),
            subtitle: searching
                ? "Измените запрос или выберите «Все треки»."
                : (playlist == nil
                    ? "Выберите папку с музыкой или перетащите файлы и M3U-плейлисты "
                        + "в окно. Обложки и альбомы подтянутся из сети."
                    : "Добавьте треки из «Все треки» через меню строки или перетащите файлы."),
            actionTitle: searching ? "Сбросить поиск" : (playlist == nil ? "Добавить папку" : "Все треки"),
            action: {
                if searching {
                    model.searchText = ""
                } else if playlist == nil {
                    chooseFolder()
                } else {
                    model.selectedPlaylistID = nil
                }
            }
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typeface.overline)
            .tracking(1.1)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    private func playlistRow(_ playlist: MusicPlaylist) -> some View {
        let isSelected = model.selectedPlaylistID == playlist.id
        return Button {
            model.selectedPlaylistID = playlist.id
        } label: {
            HStack(spacing: Space.s) {
                Text(playlist.name)
                    .font(isSelected ? Typeface.headline : Typeface.body)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 2)
                Text("\(playlist.trackCount)")
                    .font(Typeface.monoSmall)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Играть плейлист") { playPlaylist(playlist) }
            Button("Переименовать…") { model.presentRename(playlist) }
            Button("Экспорт в M3U…") {
                model.selectedPlaylistID = playlist.id
                exportPlaylist()
            }
            Divider()
            Button(role: .destructive) { pendingDeletePlaylist = playlist } label: {
                Label("Удалить плейлист", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func play(_ track: LocalTrack) {
        if track.isMissing {
            toasts.show("Файл не найден: \(track.fileName)", kind: .error)
            return
        }
        guard let index = visibleTracks.firstIndex(where: { $0.id == track.id }) else { return }
        player.playLocalTracks(visibleTracks, startingAt: index, title: queueTitle)
    }

    private func playPlaylist(_ playlist: MusicPlaylist) {
        let items = library.sorted(
            library.tracks(in: playlist.id),
            by: model.sort
        )
        guard !items.isEmpty else {
            toasts.show("Плейлист пуст", kind: .info)
            return
        }
        model.selectedPlaylistID = playlist.id
        player.playLocalTracks(items, startingAt: 0, title: playlist.name)
    }

    private func enrich(_ track: LocalTrack) {
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

    private func submit(_ prompt: MusicPlaylistPrompt, name: String) {
        switch prompt.mode {
        case .create:
            if let playlist = library.createPlaylist(name: name) {
                model.selectedPlaylistID = playlist.id
                toasts.show("Плейлист «\(playlist.name)» создан", kind: .success)
            }
        case .rename(let playlist):
            library.renamePlaylist(id: playlist.id, name: name)
            toasts.show("Плейлист переименован", kind: .success)
        }
        model.prompt = nil
    }

    // MARK: - Files

    private func chooseFolder() {
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

    private func chooseFiles() {
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

    private func handleDrop(_ urls: [URL]) -> Bool {
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

    private func importPlaylist() {
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

    private static var playlistTypes: [UTType] {
        [UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8")]
            .compactMap { $0 }
    }

    /// M3U files usually reference tracks next to them; sandboxed apps need a
    /// separate grant for that folder, so the user picks it once.
    private func runImport(_ url: URL) async {
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
            model.selectedPlaylistID = result.playlistID
            var text = "Плейлист «\(result.name)»: \(result.addedTracks) новых треков"
            if result.skippedEntries > 0 {
                text += ", пропущено \(result.skippedEntries)"
            }
            toasts.show(text, kind: .success)
        } catch {
            toasts.show(error.localizedDescription, kind: .error)
        }
    }

    private func exportPlaylist() {
        guard let playlist = selectedPlaylist,
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

    // MARK: - Helpers

    private static func trackWord(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if (11...14).contains(mod100) { return "треков" }
        switch mod10 {
        case 1: return "трек"
        case 2, 3, 4: return "трека"
        default: return "треков"
        }
    }
}
