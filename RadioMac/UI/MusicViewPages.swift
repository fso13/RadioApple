import SwiftUI

/// Albums, artists and playlists pages of the local-music window.
extension MusicView {
    var albumsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            headingRow(
                title: "Альбомы",
                subtitle: MusicCount.albums(filteredAlbums.count),
                backTitle: nil,
                back: nil
            )

            searchLine(prompt: "Поиск альбомов")
                .padding(.top, Space.l)

            if filteredAlbums.isEmpty {
                EmptyStateView(
                    systemImage: searchNeedle.isEmpty ? "square.stack" : "magnifyingglass",
                    title: searchNeedle.isEmpty ? "Пока нет альбомов" : "Ничего не найдено",
                    subtitle: searchNeedle.isEmpty
                        ? "Добавьте папку с музыкой — альбомы соберутся из тегов треков."
                        : "Измените запрос или сбросьте поиск.",
                    actionTitle: searchNeedle.isEmpty ? "Добавить папку" : "Сбросить поиск",
                    action: {
                        if searchNeedle.isEmpty {
                            chooseFolder()
                        } else {
                            model.searchText = ""
                        }
                    }
                )
            } else {
                ScrollView {
                    MusicAlbumGrid(
                        albums: filteredAlbums,
                        onOpen: { model.openAlbum($0.id) },
                        onPlay: playAlbum,
                        onEditArtwork: { presentArtworkEditor(for: $0) }
                    )
                    .padding(.top, Space.l)
                    .padding(.bottom, Space.s)
                }
                .scrollIndicators(.automatic)
            }

            pageFooter("Обложку альбома можно заменить в меню карточки или на его странице.")
        }
    }

    var artistsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            headingRow(
                title: "Исполнители",
                subtitle: MusicCount.artists(filteredArtists.count),
                backTitle: nil,
                back: nil
            )

            searchLine(prompt: "Поиск исполнителей")
                .padding(.top, Space.l)

            if filteredArtists.isEmpty {
                EmptyStateView(
                    systemImage: searchNeedle.isEmpty ? "person.2" : "magnifyingglass",
                    title: searchNeedle.isEmpty ? "Пока нет исполнителей" : "Ничего не найдено",
                    subtitle: searchNeedle.isEmpty
                        ? "Исполнители появятся, когда в библиотеке будут треки с тегом исполнителя."
                        : "Измените запрос или сбросьте поиск.",
                    actionTitle: searchNeedle.isEmpty ? "Добавить папку" : "Сбросить поиск",
                    action: {
                        if searchNeedle.isEmpty {
                            chooseFolder()
                        } else {
                            model.searchText = ""
                        }
                    }
                )
            } else {
                ScrollView {
                    MusicArtistGrid(
                        artists: filteredArtists,
                        onOpen: { model.openArtist($0.id) },
                        onPlay: playArtist,
                        onEditArtwork: { presentArtworkEditor(for: $0) }
                    )
                    .padding(.top, Space.l)
                    .padding(.bottom, Space.s)
                }
                .scrollIndicators(.automatic)
            }

            pageFooter("Обложку исполнителя можно заменить в меню карточки или на его странице.")
        }
    }

    var playlistsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            headingRow(
                title: "Плейлисты",
                subtitle: MusicCount.playlists(filteredPlaylists.count),
                backTitle: nil,
                back: nil
            )

            searchLine(prompt: "Поиск плейлистов")
                .padding(.top, Space.l)

            HStack(spacing: Space.m) {
                PrimaryButton(title: "Новый плейлист", systemImage: "plus") {
                    model.presentCreatePlaylist()
                }
                SecondaryButton(title: "Импорт M3U", systemImage: "square.and.arrow.down") {
                    importPlaylist()
                }
                Spacer()
            }
            .padding(.top, Space.m)

            if filteredPlaylists.isEmpty {
                EmptyStateView(
                    systemImage: searchNeedle.isEmpty ? "music.note.list" : "magnifyingglass",
                    title: searchNeedle.isEmpty ? "Пока нет плейлистов" : "Ничего не найдено",
                    subtitle: searchNeedle.isEmpty
                        ? "Создайте плейлист или импортируйте M3U — треки останутся в библиотеке."
                        : "Измените запрос или сбросьте поиск.",
                    actionTitle: searchNeedle.isEmpty ? "Новый плейлист" : "Сбросить поиск",
                    action: {
                        if searchNeedle.isEmpty {
                            model.presentCreatePlaylist()
                        } else {
                            model.searchText = ""
                        }
                    }
                )
            } else {
                ScrollView {
                    MusicPlaylistGrid(
                        playlists: filteredPlaylists,
                        tracksFor: { library.tracks(in: $0.id) },
                        onOpen: { model.openPlaylist($0.id) },
                        onPlay: playPlaylist,
                        onRename: { model.presentRename($0) },
                        onExport: { exportPlaylist($0) },
                        onDelete: { pendingDeletePlaylist = $0 }
                    )
                    .padding(.top, Space.l)
                    .padding(.bottom, Space.s)
                }
                .scrollIndicators(.automatic)
            }

            pageFooter("Плейлисты хранят ссылки на файлы — музыка не копируется.")
        }
    }

    func playlistPage(_ playlist: MusicPlaylist) -> some View {
        tracksPage(
            title: playlist.name,
            subtitle: tracksSubtitle,
            backTitle: "Плейлисты",
            back: { model.show(.playlists) },
            prompt: "Поиск в плейлисте"
        )
    }

    func albumPage(_ album: MusicAlbum) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailToolbar(
                backTitle: model.albumParentArtistID == nil ? "Альбомы" : "Исполнители"
            ) {
                closeAlbum()
            }

            ScrollView {
                MusicAlbumDetailView(
                    album: album,
                    actions: makeTrackActions(
                        queue: playableTracks(album.tracks),
                        title: album.title,
                        isInPlaylist: false
                    ),
                    onPlay: { playAlbum(album) },
                    onEditArtwork: { presentArtworkEditor(for: album) }
                )
                .padding(.top, Space.l)
                .padding(.bottom, Space.s)
            }
            .scrollIndicators(.automatic)
        }
    }

    func artistPage(_ artist: MusicArtist) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            detailToolbar(backTitle: "Исполнители") {
                model.show(.artists)
            }

            ScrollView {
                MusicArtistDetailView(
                    artist: artist,
                    actions: makeTrackActions(
                        queue: playableTracks(artist.tracks),
                        title: artist.name,
                        isInPlaylist: false
                    ),
                    onPlay: { playArtist(artist) },
                    onEditArtwork: { presentArtworkEditor(for: artist) },
                    onOpenAlbum: { model.openAlbum($0.id, from: artist.id) },
                    onPlayAlbum: playAlbum,
                    onEditAlbumArtwork: { presentArtworkEditor(for: $0) }
                )
                .padding(.top, Space.l)
                .padding(.bottom, Space.s)
            }
            .scrollIndicators(.automatic)
        }
    }

    func pageFooter(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(Typeface.caption)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.top, Space.xs)
    }

    func closeAlbum() {
        if let artistID = model.albumParentArtistID {
            model.openArtist(artistID)
        } else {
            model.show(.albums)
        }
    }

    // MARK: - Track actions

    var emptyState: some View {
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
                    model.show(.allTracks)
                }
            }
        )
    }
}
