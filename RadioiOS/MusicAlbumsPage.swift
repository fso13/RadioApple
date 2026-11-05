import SwiftUI

/// Cover grid of the albums derived from the local library.
struct MusicAlbumsGrid: View {
    let albums: [MusicAlbum]
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
                ForEach(albums) { album in
                    MusicAlbumCardIOS(album: album, actions: actions)
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

struct MusicAlbumCardIOS: View {
    let album: MusicAlbum
    let actions: MusicActions

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    actions.openAlbum(album)
                } label: {
                    cover
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть альбом «\(album.title)»")

                Button {
                    actions.playAlbum(album)
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
                .accessibilityLabel("Играть альбом «\(album.title)»")
            }

            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)

            Text(album.artist ?? MusicCount.tracks(album.trackCount))
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .contextMenu {
            Button {
                actions.playAlbum(album)
            } label: {
                Label("Играть", systemImage: "play.fill")
            }
            Button {
                actions.openAlbum(album)
            } label: {
                Label("Открыть", systemImage: "square.stack")
            }
            if !album.isUnnamed {
                Button {
                    actions.editAlbumArtwork(album)
                } label: {
                    Label("Обложка…", systemImage: "photo")
                }
            }
        }
    }

    private var cover: some View {
        ZStack {
            palette.surfaceRaised

            RemoteImage(urlString: album.artworkURL) {
                Image(systemName: "square.stack")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(palette.separator, lineWidth: 1)
        )
    }
}

/// Album page: large cover, play button, cover editing and the track list.
struct MusicAlbumDetailScreen: View {
    let albumID: String
    let actions: MusicActions

    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.palette) private var palette

    private var album: MusicAlbum? { music.album(id: albumID) }

    var body: some View {
        Group {
            if let album {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        header(album)
                        Hairline()
                        MusicTrackListIOS(
                            tracks: album.tracks,
                            queueTitle: album.title,
                            numbered: true,
                            actions: actions
                        )
                    }
                    .padding(.bottom, Space.m)
                }
            } else {
                EmptyStateView(
                    systemImage: "square.stack",
                    title: "Альбом не найден",
                    subtitle: "Возможно, его треки удалили из библиотеки."
                )
            }
        }
        .background(palette.window)
        .navigationTitle(music.album(id: albumID)?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(palette.window, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func header(_ album: MusicAlbum) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                cover(album)

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.title2.bold())
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let artist = album.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }

                    Text(album.details)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)

                }

                Spacer(minLength: 0)
            }

            HStack(spacing: Space.s) {
                PrimaryButton(title: "Играть", systemImage: "play.fill", fullWidth: true) {
                    actions.playAlbum(album)
                }
                if !album.isUnnamed {
                    SecondaryButton(title: "Обложка", systemImage: "photo", fullWidth: true) {
                        actions.editAlbumArtwork(album)
                    }
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private func cover(_ album: MusicAlbum) -> some View {
        ZStack {
            palette.surfaceRaised

            RemoteImage(urlString: album.artworkURL) {
                Image(systemName: "square.stack")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 124, height: 124)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(palette.separator, lineWidth: 1)
        )
    }
}
