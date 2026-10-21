import AppKit
import SwiftUI

/// Process-wide image cache for station logos and artwork.
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 160
    }

    func image(for url: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: url as NSString)
    }

    func store(_ image: NSImage, for url: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: url as NSString)
    }

    func load(_ urlString: String) async -> NSImage? {
        if let cached = image(for: urlString) { return cached }
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("RadioMac/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            return nil
        }
        guard let image = NSImage(data: data), image.size.width > 0 else { return nil }
        store(image, for: urlString)
        return image
    }
}

/// Async image with a graceful fallback, backed by `ImageCache`.
struct RemoteImage<Fallback: View>: View {
    private let urlString: String?
    private let contentMode: ContentMode
    private let fallback: Fallback

    @State private var image: NSImage?

    init(
        urlString: String?,
        contentMode: ContentMode = .fill,
        @ViewBuilder fallback: () -> Fallback
    ) {
        self.urlString = urlString
        self.contentMode = contentMode
        self.fallback = fallback()
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                fallback
            }
        }
        .task(id: urlString) {
            guard let urlString, urlString.isEmpty == false else {
                image = nil
                return
            }
            if let cached = ImageCache.shared.image(for: urlString) {
                image = cached
                return
            }
            image = await ImageCache.shared.load(urlString)
        }
    }
}
