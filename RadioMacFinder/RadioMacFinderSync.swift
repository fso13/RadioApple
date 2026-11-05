import AppKit
import FinderSync
import Foundation

/// Finder Sync extension: adds “Проиграть в RadioMac” to audio files and
/// “Создать плейлист в RadioMac” to folders in the Finder context menu.
///
/// The extension never reads the files: it asks Launch Services to open the
/// selected items with RadioMac, which both activates the app and grants it
/// read access to the selection through the sandbox.
final class RadioMacFinderSync: FIFinderSync {
    override init() {
        super.init()
        // The menu is useful in every folder, not in one client directory, so
        // the extension monitors each mounted volume.
        FIFinderSyncController.default().directoryURLs = Self.monitoredDirectories()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selection = FinderMenuPlanner.plan(for: Self.selectedURLs())
        else { return nil }

        let menu = NSMenu(title: "RadioMac")
        let item = NSMenuItem(
            title: FinderStrings.menuTitle(for: selection.action),
            action: #selector(performFinderAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.image = NSImage(
            systemSymbolName: "dot.radiowaves.left.and.right",
            accessibilityDescription: "RadioMac"
        )
        menu.addItem(item)
        return menu
    }

    /// The Finder re-asks the principal object for the selection when the user
    /// picks the item, so the plan is rebuilt from the same URLs.
    @objc private func performFinderAction(_ sender: Any?) {
        guard let selection = FinderMenuPlanner.plan(for: Self.selectedURLs()) else { return }
        FinderLauncher.open(selection)
    }

    private static func selectedURLs() -> [URL] {
        FIFinderSyncController.default().selectedItemURLs() ?? []
    }

    private static func monitoredDirectories() -> Set<URL> {
        var urls = Set<URL>()
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        urls.formUnion(volumes)
        urls.insert(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
        urls.insert(URL(fileURLWithPath: "/Users/Shared", isDirectory: true))
        return urls
    }
}

/// Hands a Finder selection over to the RadioMac app.
enum FinderLauncher {
    static func open(_ selection: FinderSelection) {
        let request = request(for: selection)
        guard let appURL = applicationURL else {
            FinderBridge.post(request)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(
            selection.urls,
            withApplicationAt: appURL,
            configuration: configuration
        ) { _, error in
            guard let error else { return }
            // Launch Services refused the items; keep the reason where the app
            // and a bug report can find it, then let a running app try itself.
            FinderBridge.report(error, for: request)
            FinderBridge.post(request)
        }
    }

    private static func request(for selection: FinderSelection) -> FinderRequest {
        FinderRequest(action: selection.action, paths: selection.urls.map(\.path))
    }

    /// `RadioMac.app/Contents/PlugIns/RadioMacFinder.appex` → `RadioMac.app`.
    private static var applicationURL: URL? {
        let url = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return url.pathExtension == "app" ? url : nil
    }
}

/// Menu titles come from the app's string catalog, so the Finder menu is
/// translated together with the rest of the app.
enum FinderStrings {
    static func menuTitle(for action: FinderAction) -> String {
        NSLocalizedString(action.menuTitleKey, bundle: appBundle, comment: "")
    }

    private static var appBundle: Bundle {
        let url = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return Bundle(url: url) ?? .main
    }
}
