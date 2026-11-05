#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// The native bitmap type of the current platform: `NSImage` on macOS,
/// `UIImage` on iOS. Shared services (image cache, Now Playing artwork)
/// allocate this type; each view converts it at the boundary.
#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    /// Decodes image data, rejecting empty or undecodable payloads.
    static func decoded(from data: Data) -> PlatformImage? {
        #if os(macOS)
        guard let image = NSImage(data: data), image.size.width > 0 else { return nil }
        return image
        #else
        guard let image = UIImage(data: data), image.size.width > 0 else { return nil }
        return image
        #endif
    }

    var platformSize: CGSize { size }
}

extension Image {
    /// SwiftUI image from the platform bitmap without spelling out
    /// `Image(nsImage:)` / `Image(uiImage:)` at every call site.
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension View {
    /// Hover highlighting is a pointer affordance; on touch platforms the
    /// modifier compiles away.
    @ViewBuilder
    func hoverHighlight(_ isHovering: Binding<Bool>) -> some View {
        onHoverCompat { isHovering.wrappedValue = $0 }
    }

    /// `onHover` is macOS-only; shared controls use this wrapper so the same
    /// source compiles for the iPhone.
    @ViewBuilder
    func onHoverCompat(_ action: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        onHover(perform: action)
        #else
        self
        #endif
    }

    /// Tooltip on macOS, accessibility hint elsewhere.
    @ViewBuilder
    func helpCompat(_ text: String) -> some View {
        #if os(macOS)
        help(text)
        #else
        accessibilityHint(text)
        #endif
    }
}
