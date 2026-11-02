import SwiftUI

/// Library navigation: all tracks, expandable albums and artists, playlists.
extension MusicView {
    var sidebar: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            sectionLabel("Библиотека")

            NavItem(
                label: "Все треки",
                isSelected: model.page == .allTracks,
                isPlaying: player.isLocalPlayback && player.isPlaying
            ) {
                model.show(.allTracks)
            }

            expandableNavRow(
                title: "Альбомы",
                page: .albums,
                isExpanded: model.albumsExpanded
            ) {
                withAnimation(Motion.content) {
                    model.toggleAlbums()
                }
            }
            if model.albumsExpanded {
                sidebarAlbumList
            }

            expandableNavRow(
                title: "Исполнители",
                page: .artists,
                isExpanded: model.artistsExpanded
            ) {
                withAnimation(Motion.content) {
                    model.toggleArtists()
                }
            }
            if model.artistsExpanded {
                sidebarArtistList
            }

            NavItem(
                label: "Плейлисты",
                isSelected: model.page == .playlists,
                isPlaying: player.isLocalPlayback && player.isPlaying
            ) {
                model.show(.playlists)
            }

            Spacer(minLength: Space.s)

            TextButton(title: "Источники…", systemImage: "folder") {
                showSources = true
            }
        }
        .frame(width: 178)
    }

    func expandableNavRow(
        title: String,
        page: MusicPage,
        isExpanded: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            NavItem(
                label: title,
                isSelected: model.page == page
            ) {
                model.show(page)
            }
            .layoutPriority(1)

            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 20, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Свернуть" : "Развернуть")
            .accessibilityLabel(isExpanded ? "Свернуть «\(title)»" : "Развернуть «\(title)»")
        }
    }

    var sidebarAlbumList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if albums.isEmpty {
                    sidebarEmptyRow("Пока нет альбомов")
                } else {
                    ForEach(albums) { album in
                        sidebarAlbumRow(album)
                    }
                }
            }
            .padding(.vertical, Space.xxs)
        }
        .frame(height: sidebarListHeight(count: albums.count, rowHeight: 26))
        .scrollIndicators(.hidden)
    }

    var sidebarArtistList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if artists.isEmpty {
                    sidebarEmptyRow("Пока нет исполнителей")
                } else {
                    ForEach(artists) { artist in
                        sidebarCollectionRow(
                            artist.name,
                            isSelected: model.selectedArtistID == artist.id
                        ) {
                            model.openArtist(artist.id)
                        }
                    }
                }
            }
            .padding(.vertical, Space.xxs)
        }
        .frame(height: sidebarListHeight(count: artists.count, rowHeight: 17))
        .scrollIndicators(.hidden)
    }

    func sidebarListHeight(count: Int, rowHeight: CGFloat) -> CGFloat {
        min(CGFloat(max(count, 1)) * rowHeight + 6, 190)
    }

    func sidebarAlbumRow(_ album: MusicAlbum) -> some View {
        let isSelected = model.selectedAlbumID == album.id
        return Button {
            model.openAlbum(album.id)
        } label: {
            HStack(spacing: Space.xs) {
                Rectangle()
                    .fill(isSelected ? palette.textPrimary : Color.clear)
                    .frame(width: 2, height: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(album.title)
                        .font(isSelected ? Typeface.captionMedium : Typeface.caption)
                        .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let artist = album.artist {
                        Text(artist)
                            .font(Typeface.caption)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Space.m)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? palette.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
        .help(album.artist.map { "\(album.title) — \($0)" } ?? album.title)
    }

    func sidebarCollectionRow(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Rectangle()
                    .fill(isSelected ? palette.textPrimary : Color.clear)
                    .frame(width: 2, height: 11)
                Text(title)
                    .font(isSelected ? Typeface.captionMedium : Typeface.caption)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, Space.m)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? palette.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    func sidebarEmptyRow(_ text: String) -> some View {
        Text(text)
            .font(Typeface.caption)
            .foregroundStyle(palette.textTertiary)
            .padding(.leading, Space.l)
            .padding(.vertical, 3)
    }

    // MARK: - Track pages
}
