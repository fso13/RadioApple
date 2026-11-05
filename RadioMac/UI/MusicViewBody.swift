import SwiftUI

/// The music page body and its modifier chain.
///
/// The chain is split into small steps so the type checker stays fast: Xcode 16
/// otherwise fails the whole `body` with “unable to type-check this expression in
/// reasonable time”. Sheets, drag-and-drop and observers are separate layers.
extension MusicView {
    var body: some View {
        panelWithObservers
    }

    /// The panel and its modifier chain is split into small steps: Xcode 16
    /// gives up on the whole expression with “unable to type-check … in
    /// reasonable time”, while the pieces compile quickly everywhere.
    var panelWithObservers: some View {
        trackObservers(selectionObservers(panelWithSheets))
    }

    var panelWithSheets: some View {
        panelWithDrop
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
            .sheet(item: $artworkEditor) { editor in
                MusicArtworkEditorView(editor: editor)
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
                    if model.selectedPlaylistID == playlist.id {
                        model.show(.playlists)
                    }
                    toasts.show("Плейлист «\(playlist.name)» удалён", kind: .success)
                    pendingDeletePlaylist = nil
                }
            } message: { _ in
                Text("Треки останутся в библиотеке — удалится только список.")
            }
    }

    var panelWithDrop: some View {
        panel
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
    }

    var panel: some View {
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
    }

    func trackObservers<Content: View>(_ view: Content) -> some View {
        view
            .onChange(of: player.status) { _, newValue in
                guard newValue == .error else { return }
                toasts.show(player.consumeError() ?? "Не удалось открыть файл", kind: .error)
            }
            .onChange(of: model.focusSearchToken) { _, _ in searchFocused = true }
            .onChange(of: model.resignSearchToken) { _, _ in searchFocused = false }
            .onAppear(perform: recomputeAll)
            .onChange(of: library.tracks) { _, tracks in
                recomputeAll()
                guard let current = player.localTrack,
                      let fresh = tracks.first(where: { $0.id == current.id })
                else { return }
                if fresh != current { player.refreshLocalTrack(fresh) }
            }
            .onChange(of: library.playlists) { _, playlists in
                recomputeVisibleTracks()
                guard let id = model.selectedPlaylistID,
                      !playlists.contains(where: { $0.id == id })
                else { return }
                model.show(.playlists)
            }
            .onChange(of: library.artistArtwork) { _, _ in recomputeCollections() }
    }

    func selectionObservers<Content: View>(_ view: Content) -> some View {
        view
            .onChange(of: model.searchText) { _, _ in recomputeVisibleTracks() }
            .onChange(of: model.selectedPlaylistID) { _, _ in recomputeVisibleTracks() }
            .onChange(of: model.sort) { _, _ in recomputeVisibleTracks() }
            .onChange(of: model.grouping) { _, _ in recomputeVisibleTracks() }
    }
}
