import SwiftUI

/// Artists derived from the local library, with circular covers.
struct MusicArtistsGrid: View {
    let artists: [MusicArtist]
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
                ForEach(artists) { artist in
                    MusicArtistCardIOS(artist: artist, actions: actions)
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

struct MusicArtistCardIOS: View {
    let artist: MusicArtist
    let actions: MusicActions

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    actions.openArtist(artist)
                } label: {
                    cover
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть исполнителя «\(artist.name)»")

                Button {
                    actions.playArtist(artist)
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
                .accessibilityLabel("Играть исполнителя «\(artist.name)»")
            }

            Text(artist.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)

            Text(artist.details)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .contextMenu {
            Button {
                actions.playArtist(artist)
            } label: {
                Label("Играть", systemImage: "play.fill")
            }
            Button {
                actions.openArtist(artist)
            } label: {
                Label("Открыть", systemImage: "person")
            }
            if !artist.isUnnamed {
                Button {
                    actions.editArtistArtwork(artist)
                } label: {
                    Label("Обложка…", systemImage: "photo")
                }
            }
        }
    }

    private var cover: some View {
        ZStack {
            palette.surfaceRaised

            RemoteImage(urlString: artist.artworkURL) {
                Image(systemName: "person")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
    }
}

/// Artist page: portrait, albums and all tracks.
struct MusicArtistDetailScreen: View {
    let artistID: String
    let actions: MusicActions

    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.palette) private var palette

    private var artist: MusicArtist? { music.artist(id: artistID) }

    var body: some View {
        Group {
            if let artist {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        header(artist)

                        if !artist.albums.isEmpty {
                            SectionLabel(title: "Альбомы")
                                .padding(.horizontal, Space.l)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: Space.m) {
                                    ForEach(artist.albums) { album in
                                        MusicAlbumCardIOS(album: album, actions: actions)
                                            .frame(width: 138)
                                    }
                                }
                                .padding(.horizontal, Space.l)
                            }
                        }

                        SectionLabel(title: "Треки")
                            .padding(.horizontal, Space.l)
                            .padding(.top, Space.xs)

                        MusicTrackListIOS(
                            tracks: artist.tracks,
                            queueTitle: artist.name,
                            actions: actions
                        )
                    }
                    .padding(.bottom, Space.m)
                }
            } else {
                EmptyStateView(
                    systemImage: "person",
                    title: "Исполнитель не найден",
                    subtitle: "Возможно, его треки удалили из библиотеки."
                )
            }
        }
        .background(palette.window)
        .navigationTitle(music.artist(id: artistID)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(palette.window, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func header(_ artist: MusicArtist) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                cover(artist)

                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.title2.bold())
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(artist.details)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)

                }

                Spacer(minLength: 0)
            }

            HStack(spacing: Space.s) {
                PrimaryButton(title: "Играть", systemImage: "play.fill", fullWidth: true) {
                    actions.playArtist(artist)
                }
                if !artist.isUnnamed {
                    SecondaryButton(title: "Обложка", systemImage: "photo", fullWidth: true) {
                        actions.editArtistArtwork(artist)
                    }
                }
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private func cover(_ artist: MusicArtist) -> some View {
        ZStack {
            palette.surfaceRaised

            RemoteImage(urlString: artist.artworkURL) {
                Image(systemName: "person")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 112, height: 112)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.separator, lineWidth: 1))
    }
}
