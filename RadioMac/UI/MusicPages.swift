import SwiftUI

/// Per-row callbacks shared by every track list: the grouped table, album
/// pages, artist pages and playlists.
struct MusicTrackActions {
    var isCurrent: (LocalTrack) -> Bool
    var isPlaying: (LocalTrack) -> Bool
    var isLoading: (LocalTrack) -> Bool
    var isInPlaylist: Bool
    var playlists: [MusicPlaylist]
    var onPlay: (LocalTrack) -> Void
    var onEnrich: (LocalTrack) -> Void
    var onEdit: (LocalTrack) -> Void
    var onAddToPlaylist: (LocalTrack, MusicPlaylist) -> Void
    var onRemoveFromPlaylist: (LocalTrack) -> Void
    var onRevealInFinder: (LocalTrack) -> Void
    var onDelete: (LocalTrack) -> Void
}

@MainActor
func musicTrackRow(_ track: LocalTrack, actions: MusicTrackActions) -> MusicTrackRow {
    MusicTrackRow(
        track: track,
        isCurrent: actions.isCurrent(track),
        isPlaying: actions.isPlaying(track),
        isLoading: actions.isLoading(track),
        isInPlaylist: actions.isInPlaylist,
        playlists: actions.playlists,
        onPlay: { actions.onPlay(track) },
        onEnrich: { actions.onEnrich(track) },
        onEdit: { actions.onEdit(track) },
        onAddToPlaylist: { playlist in actions.onAddToPlaylist(track, playlist) },
        onRemoveFromPlaylist: { actions.onRemoveFromPlaylist(track) },
        onRevealInFinder: { actions.onRevealInFinder(track) },
        onDelete: { actions.onDelete(track) }
    )
}

/// Flat track list used inside albums, artists and playlists.
struct MusicTrackList: View {
    let tracks: [LocalTrack]
    let actions: MusicTrackActions

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks) { track in
                musicTrackRow(track, actions: actions)
            }
        }
    }
}

// MARK: - Album cards

struct MusicAlbumGrid: View {
    let albums: [MusicAlbum]
    let onOpen: (MusicAlbum) -> Void
    let onPlay: (MusicAlbum) -> Void
    let onEditArtwork: (MusicAlbum) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 128, maximum: 190), spacing: Space.m, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
            ForEach(albums) { album in
                MusicAlbumCard(
                    album: album,
                    onOpen: { onOpen(album) },
                    onPlay: { onPlay(album) },
                    onEditArtwork: { onEditArtwork(album) }
                )
            }
        }
    }
}

struct MusicAlbumCard: View {
    let album: MusicAlbum
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onEditArtwork: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            artwork
            Text(album.title)
                .font(Typeface.captionMedium)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(cardSubtitle)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu { menuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [album.title, album.artist, album.details]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityHint("Открыть альбом")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
    }

    private var artwork: some View {
        ZStack {
            palette.surfaceRaised

            if let url = album.artworkURL {
                RemoteImage(urlString: url) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if hovering && !album.isUnnamed {
                Button(action: onEditArtwork) {
                    Image(systemName: "photo")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(palette.surface.opacity(0.9)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(Space.scrollLane)
                .help("Изменить обложку")
                .accessibilityLabel("Изменить обложку альбома «\(album.title)»")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                playButton
                    .padding(Space.scrollLane)
                    .transition(.opacity)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "square.stack")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }

    private var cardSubtitle: String {
        if let artist = album.artist { return artist }
        return album.isUnnamed ? MusicCount.tracks(album.trackCount) : "Без исполнителя"
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(palette.accentFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Играть альбом")
        .accessibilityLabel("Играть альбом «\(album.title)»")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onOpen) {
            Label("Открыть", systemImage: "square.stack")
        }
        Button(action: onPlay) {
            Label("Играть альбом", systemImage: "play")
        }
        if !album.isUnnamed {
            Divider()
            Button(action: onEditArtwork) {
                Label("Обложка…", systemImage: "photo")
            }
        }
    }
}

// MARK: - Artist cards

struct MusicArtistGrid: View {
    let artists: [MusicArtist]
    let onOpen: (MusicArtist) -> Void
    let onPlay: (MusicArtist) -> Void
    let onEditArtwork: (MusicArtist) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 128, maximum: 190), spacing: Space.m, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
            ForEach(artists) { artist in
                MusicArtistCard(
                    artist: artist,
                    onOpen: { onOpen(artist) },
                    onPlay: { onPlay(artist) },
                    onEditArtwork: { onEditArtwork(artist) }
                )
            }
        }
    }
}

struct MusicArtistCard: View {
    let artist: MusicArtist
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onEditArtwork: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        VStack(spacing: Space.xs) {
            artwork
            Text(artist.name)
                .font(Typeface.captionMedium)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(artist.details)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu { menuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artist.name), \(artist.details)")
        .accessibilityHint("Открыть исполнителя")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
    }

    private var artwork: some View {
        ZStack {
            palette.surfaceRaised

            if let url = artist.artworkURL {
                RemoteImage(urlString: url) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
        .overlay(alignment: .center) {
            if hovering {
                playButton
                    .transition(.opacity)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "person")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(palette.accentFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Играть исполнителя")
        .accessibilityLabel("Играть «\(artist.name)»")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onOpen) {
            Label("Открыть", systemImage: "person")
        }
        Button(action: onPlay) {
            Label("Играть исполнителя", systemImage: "play")
        }
        if !artist.isUnnamed {
            Divider()
            Button(action: onEditArtwork) {
                Label("Обложка…", systemImage: "photo")
            }
        }
    }
}

// MARK: - Playlist cards

struct MusicPlaylistGrid: View {
    let playlists: [MusicPlaylist]
    let tracksFor: (MusicPlaylist) -> [LocalTrack]
    let onOpen: (MusicPlaylist) -> Void
    let onPlay: (MusicPlaylist) -> Void
    let onRename: (MusicPlaylist) -> Void
    let onExport: (MusicPlaylist) -> Void
    let onDelete: (MusicPlaylist) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 128, maximum: 190), spacing: Space.m, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Space.l) {
            ForEach(playlists) { playlist in
                MusicPlaylistCard(
                    playlist: playlist,
                    tracks: tracksFor(playlist),
                    onOpen: { onOpen(playlist) },
                    onPlay: { onPlay(playlist) },
                    onRename: { onRename(playlist) },
                    onExport: { onExport(playlist) },
                    onDelete: { onDelete(playlist) }
                )
            }
        }
    }
}

struct MusicPlaylistCard: View {
    let playlist: MusicPlaylist
    let tracks: [LocalTrack]
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onRename: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            cover
            Text(playlist.name)
                .font(Typeface.captionMedium)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(MusicCount.tracks(playlist.trackCount))
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .contextMenu { menuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(playlist.name), \(MusicCount.tracks(playlist.trackCount))")
        .accessibilityHint("Открыть плейлист")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
    }

    private var cover: some View {
        ZStack {
            MusicPlaylistCover(tracks: tracks)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(palette.accentFill))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(Space.scrollLane)
                .help("Играть плейлист")
                .accessibilityLabel("Играть плейлист «\(playlist.name)»")
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onOpen) {
            Label("Открыть", systemImage: "music.note.list")
        }
        Button(action: onPlay) {
            Label("Играть плейлист", systemImage: "play")
        }
        Divider()
        Button(action: onRename) {
            Label("Переименовать…", systemImage: "pencil")
        }
        Button(action: onExport) {
            Label("Экспорт в M3U…", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Удалить плейлист", systemImage: "trash")
        }
    }
}

/// A 2×2 mosaic of the playlist's covers, with an icon for empty playlists.
struct MusicPlaylistCover: View {
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

// MARK: - Album and artist pages

struct MusicAlbumDetailView: View {
    let album: MusicAlbum
    let actions: MusicTrackActions
    let onPlay: () -> Void
    let onEditArtwork: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            Hairline()
            MusicTrackList(tracks: album.tracks, actions: actions)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.l) {
            cover
            VStack(alignment: .leading, spacing: Space.s) {
                Text(album.title)
                    .font(Typeface.pageTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                if let artist = album.artist {
                    Text(artist)
                        .font(Typeface.callout)
                        .foregroundStyle(palette.textSecondary)
                }
                Text(album.details)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: Space.m) {
                    PrimaryButton(title: "Играть", systemImage: "play.fill") {
                        onPlay()
                    }
                    if !album.isUnnamed {
                        SecondaryButton(title: "Обложка…", systemImage: "photo") {
                            onEditArtwork()
                        }
                    }
                }
                .padding(.top, Space.xs)
            }
            Spacer(minLength: 0)
        }
    }

    private var cover: some View {
        ZStack {
            palette.surfaceRaised
            if let url = album.artworkURL {
                RemoteImage(urlString: url) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 168, height: 168)
        .clipped()
        .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
    }

    private var placeholder: some View {
        Image(systemName: "square.stack")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }
}

struct MusicArtistDetailView: View {
    let artist: MusicArtist
    let actions: MusicTrackActions
    let onPlay: () -> Void
    let onEditArtwork: () -> Void
    let onOpenAlbum: (MusicAlbum) -> Void
    let onPlayAlbum: (MusicAlbum) -> Void
    let onEditAlbumArtwork: (MusicAlbum) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header

            if !artist.albums.isEmpty {
                sectionLabel("Альбомы")
                MusicAlbumGrid(
                    albums: artist.albums,
                    onOpen: onOpenAlbum,
                    onPlay: onPlayAlbum,
                    onEditArtwork: onEditAlbumArtwork
                )
            }

            sectionLabel("Треки")
            MusicTrackList(tracks: artist.tracks, actions: actions)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.l) {
            cover
            VStack(alignment: .leading, spacing: Space.s) {
                Text(artist.name)
                    .font(Typeface.pageTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(artist.details)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: Space.m) {
                    PrimaryButton(title: "Играть", systemImage: "play.fill") {
                        onPlay()
                    }
                    if !artist.isUnnamed {
                        SecondaryButton(title: "Обложка…", systemImage: "photo") {
                            onEditArtwork()
                        }
                    }
                }
                .padding(.top, Space.xs)
            }
            Spacer(minLength: 0)
        }
    }

    private var cover: some View {
        ZStack {
            palette.surfaceRaised
            if let url = artist.artworkURL {
                RemoteImage(urlString: url) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 168, height: 168)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
    }

    private var placeholder: some View {
        Image(systemName: "person")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typeface.overline)
            .tracking(1.2)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s)
            .accessibilityAddTraits(.isHeader)
    }
}
