import Foundation

/// Request to change the cover of an album or an artist.
///
/// The sheet is platform-specific (AppKit file panels on macOS, Files on iOS),
/// but the request itself and the online search closure are shared.
struct MusicArtworkEditor: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let note: String?
    let currentURL: String?
    /// Online covers for this album or artist; called from the sheet.
    let search: @MainActor () async -> [TrackEnrichment]
    /// Applies the picked URL, or removes the cover when `nil`.
    let save: @MainActor (String?) -> Void

    init(
        title: String,
        subtitle: String?,
        note: String? = nil,
        currentURL: String?,
        search: @escaping @MainActor () async -> [TrackEnrichment],
        save: @escaping @MainActor (String?) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.note = note
        self.currentURL = currentURL
        self.search = search
        self.save = save
    }
}
