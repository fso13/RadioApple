import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// Presents the system music picker from the key window.
///
/// `MPMediaPickerController` is a modal UIKit controller and expects to be
/// presented directly; embedding it in a SwiftUI hosting controller crashes.
@MainActor
final class MediaLibraryPresenter: NSObject, @preconcurrency MPMediaPickerControllerDelegate {
    static let shared = MediaLibraryPresenter()

    private weak var picker: MPMediaPickerController?
    private var onPicked: (([MPMediaItem]) -> Void)?
    private var onCancel: (() -> Void)?

    func present(
        onPicked: @escaping ([MPMediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard picker == nil,
              let presenter = Self.topViewController()
        else { return }

        self.onPicked = onPicked
        self.onCancel = onCancel

        let controller = MPMediaPickerController(mediaTypes: .music)
        controller.delegate = self
        controller.allowsPickingMultipleItems = true
        controller.showsCloudItems = false
        controller.showsItemsWithProtectedAssets = false
        controller.prompt = "Песни, загруженные на этот iPhone"
        picker = controller

        presenter.present(controller, animated: true)
    }

    func mediaPicker(
        _ mediaPicker: MPMediaPickerController,
        didPickMediaItems mediaItemCollection: MPMediaItemCollection
    ) {
        let items = mediaItemCollection.items
        let completion = onPicked
        finish(mediaPicker)
        completion?(items)
    }

    func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
        let completion = onCancel
        finish(mediaPicker)
        completion?()
    }

    private func finish(_ mediaPicker: MPMediaPickerController) {
        onPicked = nil
        onCancel = nil
        mediaPicker.dismiss(animated: true)
        picker = nil
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first,
              let root = window.rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Exports a local media-library item into the app's temporary directory.
/// Apple Music streaming/cloud tracks have no `assetURL` and are rejected.
enum MediaLibraryExporter {
    @MainActor
    static func export(_ item: MPMediaItem) async -> URL? {
        guard !item.isCloudItem,
              !item.hasProtectedAsset,
              let assetURL = item.assetURL
        else { return nil }

        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return nil }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: item))
        try? FileManager.default.removeItem(at: destination)

        do {
            #if compiler(>=6.2)
            try await session.export(to: destination, as: .m4a)
            #else
            // Xcode 16 / iOS 18 SDK has no async export API yet.
            session.outputURL = destination
            session.outputFileType = .m4a
            session.exportAsynchronously {}
            while session.status == .waiting || session.status == .exporting {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard session.status == .completed else {
                try? FileManager.default.removeItem(at: destination)
                return nil
            }
            #endif
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    private static func fileName(for item: MPMediaItem) -> String {
        let parts = [item.artist, item.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let raw = parts.isEmpty ? "Песня" : parts.joined(separator: " - ")
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .prefix(90)
        return "\(cleaned).m4a"
    }
}
