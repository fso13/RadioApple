import SwiftUI

/// Playlist covers: a 2×2 mosaic of the first four track covers.
struct MusicPlaylistCoverIOS: View {
    let tracks: [LocalTrack]

    @Environment(\.palette) private var palette

    private var artworkURLs: [String] {
        tracks.compactMap(\.artworkURL).filter { !$0.isEmpty }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = (proxy.size.width - 1) / 2
            let height = (proxy.size.height - 1) / 2

            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    tile(0).frame(width: width, height: height)
                    tile(1).frame(width: width, height: height)
                }
                HStack(spacing: 1) {
                    tile(2).frame(width: width, height: height)
                    tile(3).frame(width: width, height: height)
                }
            }
        }
        .background(palette.surfaceRaised)
    }

    private func tile(_ index: Int) -> some View {
        ZStack {
            palette.surfaceRaised

            if index < artworkURLs.count {
                RemoteImage(urlString: artworkURLs[index]) {
                    emptyTile
                }
            } else {
                emptyTile
            }
        }
        .clipped()
    }

    private var emptyTile: some View {
        Image(systemName: "music.note")
            .font(.system(size: 10, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }
}

struct MusicPlaylistsGrid: View {
    let playlists: [MusicPlaylist]
    let actions: MusicActions

    @EnvironmentObject private var music: MusicLibrary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [
                GridItem(.flexible(), spacing: Space.m),
                GridItem(.flexible(), spacing: Space.m),
            ]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
                ForEach(playlists) { playlist in
                    MusicPlaylistCardIOS(playlist: playlist, actions: actions)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .refreshable {
            music.rescan()
        }
    }
}

struct MusicPlaylistCardIOS: View {
    let playlist: MusicPlaylist
    let actions: MusicActions

    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.palette) private var palette

    private var tracks: [LocalTrack] { music.tracks(in: playlist.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    actions.openPlaylist(playlist)
                } label: {
                    ZStack {
                        MusicPlaylistCoverIOS(tracks: tracks)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .overlay(
                        Rectangle().strokeBorder(palette.separator, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть плейлист «\(playlist.name)»")

                Button {
                    actions.playPlaylist(playlist)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(palette.accentFill))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(2)
                .accessibilityLabel("Играть плейлист «\(playlist.name)»")
            }

            Text(playlist.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)

            Text(MusicCount.tracks(playlist.trackCount))
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .contextMenu {
            Button {
                actions.openPlaylist(playlist)
            } label: {
                Label("Открыть", systemImage: "music.note.list")
            }
            Button {
                actions.playPlaylist(playlist)
            } label: {
                Label("Играть", systemImage: "play.fill")
            }
            Button {
                actions.addTracksToPlaylist(playlist)
            } label: {
                Label("Добавить треки…", systemImage: "plus")
            }
            Button {
                actions.renamePlaylist(playlist)
            } label: {
                Label("Переименовать…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                actions.deletePlaylist(playlist)
            } label: {
                Label("Удалить плейлист", systemImage: "trash")
            }
        }
    }
}

/// Playlist page: cover, play, track management.
struct MusicPlaylistDetailScreen: View {
    let playlistID: String
    let actions: MusicActions

    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.palette) private var palette

    private var playlist: MusicPlaylist? { music.playlist(id: playlistID) }
    private var tracks: [LocalTrack] { music.tracks(in: playlistID) }

    var body: some View {
        Group {
            if let playlist {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        header(playlist)

                        if tracks.isEmpty {
                            EmptyStateView(
                                systemImage: "music.note.list",
                                title: "Плейлист пуст",
                                subtitle: "Добавьте треки из библиотеки — они останутся в исходных альбомах.",
                                actionTitle: "Добавить треки",
                                action: { actions.addTracksToPlaylist(playlist) }
                            )
                            .padding(.horizontal, Space.l)
                            .padding(.top, Space.l)
                        } else {
                            Hairline()

                            MusicTrackListIOS(
                                tracks: tracks,
                                queueTitle: playlist.name,
                                playlist: playlist,
                                actions: actions
                            )
                        }
                    }
                    .padding(.bottom, Space.m)
                }
            } else {
                EmptyStateView(
                    systemImage: "music.note.list",
                    title: "Плейлист не найден",
                    subtitle: "Возможно, его удалили."
                )
            }
        }
        .background(palette.window)
        .navigationTitle(music.playlist(id: playlistID)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(palette.window, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let playlist {
                    playlistMenu(playlist)
                }
            }
        }
    }

    private func playlistMenu(_ playlist: MusicPlaylist) -> some View {
        Menu {
            Button {
                actions.addTracksToPlaylist(playlist)
            } label: {
                Label("Добавить треки…", systemImage: "plus")
            }
            Button {
                actions.renamePlaylist(playlist)
            } label: {
                Label("Переименовать…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                actions.deletePlaylist(playlist)
            } label: {
                Label("Удалить плейлист", systemImage: "trash")
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

    private func header(_ playlist: MusicPlaylist) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                cover

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.title2.bold())
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(details)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)

                }

                Spacer(minLength: 0)
            }

            HStack(spacing: Space.s) {
                PrimaryButton(title: "Играть", systemImage: "play.fill", fullWidth: true) {
                    actions.playPlaylist(playlist)
                }
                .disabled(tracks.isEmpty)

                SecondaryButton(title: "Добавить", systemImage: "plus", fullWidth: true) {
                    actions.addTracksToPlaylist(playlist)
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private var details: String {
        let count = MusicCount.tracks(tracks.count)
        guard !tracks.isEmpty else { return count }
        return "\(count) · \(LocalTrack.totalDurationText(tracks))"
    }

    private var cover: some View {
        MusicPlaylistCoverIOS(tracks: tracks)
            .frame(width: 124, height: 124)
            .clipped()
            .overlay(
                Rectangle().strokeBorder(palette.separator, lineWidth: 1)
            )
    }
}

/// Create or rename a playlist.
struct MusicPlaylistNameSheet: View {
    let request: PlaylistPromptRequest
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var name: String

    init(request: PlaylistPromptRequest, onSave: @escaping (String) -> Void) {
        self.request = request
        self.onSave = onSave
        _name = State(initialValue: request.initialName)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text(request.title)
                    .font(.title3.bold())
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                CircleIconButton(systemName: "xmark", size: 12, help: "Закрыть") {
                    dismiss()
                }
            }

            EditorialField(title: "Название", text: $name, placeholder: "Например, Утро")

            HStack {
                TextButton(title: "Отмена") { dismiss() }
                Spacer()
                PrimaryButton(title: "Сохранить", isEnabled: !trimmed.isEmpty) {
                    onSave(trimmed)
                    dismiss()
                }
            }
        }
        .padding(Space.xl)
        .presentationDetents([.medium])
        .background(palette.surface)
    }
}

/// Multi-select sheet that adds library tracks to a playlist.
struct MusicTrackPickerSheet: View {
    let playlist: MusicPlaylist

    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var query = ""
    @State private var selected: Set<String> = []

    private var existing: Set<String> { Set(music.tracks(in: playlist.id).map(\.id)) }

    private var tracks: [LocalTrack] {
        music.filteredTracks(query: query, playlistID: nil, sort: .artist)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            SearchFieldIOS(text: $query, placeholder: "Название, исполнитель, альбом")
                .padding(.bottom, Space.s)

            Hairline()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        row(track)
                        Hairline(inset: 64)
                    }
                }
                .padding(.bottom, Space.m)
            }
        }
        .background(palette.window)
        .presentationDetents([.large])
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Добавить в плейлист")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Text(playlist.name)
                    .font(.title3.bold())
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                let ids = selected.filter { !existing.contains($0) }
                music.addTracks(Array(ids), to: playlist.id)
                dismiss()
            } label: {
                Text(selected.isEmpty ? "Готово" : "Добавить \(selected.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(palette.accentFill.opacity(selected.isEmpty ? 0.5 : 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.m)
    }

    private func row(_ track: LocalTrack) -> some View {
        let alreadyThere = existing.contains(track.id)
        let isSelected = selected.contains(track.id)

        return HStack(spacing: Space.m) {
            ZStack {
                palette.surfaceRaised

                RemoteImage(urlString: track.artworkURL) {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(width: 38, height: 38)
            .clipped()
            .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text([track.displayArtist, track.displayAlbum].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s)

            Image(
                systemName: alreadyThere
                    ? "checkmark.circle.fill"
                    : (isSelected ? "checkmark.circle.fill" : "circle")
            )
            .font(.system(size: 20))
            .frame(width: 44, height: 44)
            .foregroundStyle(
                alreadyThere
                    ? palette.textTertiary
                    : (isSelected ? palette.textPrimary : palette.textTertiary.opacity(0.6))
            )
        }
        .padding(.horizontal, Space.l)
        .frame(height: 56)
        .contentShape(Rectangle())
        .opacity(alreadyThere ? 0.55 : 1)
        .onTapGesture {
            guard !alreadyThere else { return }
            if isSelected {
                selected.remove(track.id)
            } else {
                selected.insert(track.id)
            }
        }
    }
}
