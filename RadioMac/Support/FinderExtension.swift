import AppKit
import FinderSync

/// Host-side view of the Finder Sync extension.
///
/// macOS keeps Finder extensions switched off until the user enables them, so
/// the settings page reports the state and opens the system interface where the
/// extension can be turned on.
enum FinderExtension {
    /// Whether the user has enabled "RadioMac" in the Finder extensions list.
    static var isEnabled: Bool {
        FIFinderSyncController.isExtensionEnabled
    }

    static func showSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
