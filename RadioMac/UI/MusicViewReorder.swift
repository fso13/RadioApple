import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Drag-to-reorder for the custom track order.
extension MusicView {
    /// Drag-to-reorder works only for a flat, unfiltered list: groups and
    /// search make the visible order a projection of the library.
    var canReorderTracks: Bool {
        guard visibleTracks.count > 1 else { return false }
        guard model.grouping == .none else { return false }
        guard model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return model.page == .allTracks || selectedPlaylist != nil
    }

    @ViewBuilder
    func reorderableTrackRow(_ track: LocalTrack) -> some View {
        if canReorderTracks {
            musicTrackRow(track, actions: trackPageActions)
                .onDrag {
                    NSItemProvider(object: track.id as NSString)
                }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleTrackDrop(providers) { id in
                        moveTrack(id, before: track.id)
                    }
                }
        } else {
            musicTrackRow(track, actions: trackPageActions)
        }
    }

    /// Loads the dragged track id and applies the move on the main queue.
    func handleTrackDrop(
        _ providers: [NSItemProvider],
        onDrop: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? NSString else { return }
            let id = value as String
            Task { @MainActor in onDrop(id) }
        }
        return true
    }

    func moveTrack(_ id: String, before targetID: String) {
        guard canReorderTracks, id != targetID,
              let from = visibleTracks.firstIndex(where: { $0.id == id }),
              let target = visibleTracks.firstIndex(where: { $0.id == targetID })
        else { return }
        var items = visibleTracks
        let track = items.remove(at: from)
        let insertion = from < target ? target - 1 : target
        items.insert(track, at: insertion)
        applyTrackOrder(items)
    }

    func moveTrackToEnd(_ id: String) {
        guard canReorderTracks,
              let from = visibleTracks.firstIndex(where: { $0.id == id }),
              from != visibleTracks.count - 1
        else { return }
        var items = visibleTracks
        let track = items.remove(at: from)
        items.append(track)
        applyTrackOrder(items)
    }

    /// Writes the visible order back as the custom order and switches to it,
    /// so the row does not jump after the drop.
    func applyTrackOrder(_ items: [LocalTrack]) {
        let ids = items.map(\.id)
        if let playlist = selectedPlaylist {
            library.setTrackOrder(ids, in: playlist.id)
        } else {
            library.setTrackOrder(ids)
        }
        if model.sort != .manual {
            model.sort = .manual
        }
    }
}
