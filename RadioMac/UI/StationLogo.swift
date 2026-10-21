import SwiftUI

/// Station artwork. Square and sharp, like the reference photography.
struct StationLogo: View {
    let station: RadioStation
    var size: CGFloat = 36
    var imageURL: String?

    @Environment(\.palette) private var palette

    private var resolvedURL: String? {
        if let override = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        return station.hasLogo ? station.logoURL : nil
    }

    var body: some View {
        ZStack {
            palette.surfaceRaised

            RemoteImage(urlString: resolvedURL) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: size * 0.32, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay(
            Rectangle()
                .strokeBorder(palette.separator, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
