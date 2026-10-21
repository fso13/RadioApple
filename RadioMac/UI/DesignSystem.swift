import SwiftUI

// MARK: - Tokens

/// 4-point spacing grid.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 40
}

/// Nearly square corners, like the reference: print-like, not bubbly.
enum Radius {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 3
    static let md: CGFloat = 4
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
}

/// Type scale. System SF Pro, one family, weight and size carry hierarchy.
enum Typeface {
    static let hero = Font.system(size: 30, weight: .bold)
    static let pageTitle = Font.system(size: 24, weight: .bold)
    static let nav = Font.system(size: 22, weight: .regular)
    static let navActive = Font.system(size: 22, weight: .semibold)
    static let section = Font.system(size: 16, weight: .semibold)
    static let headline = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let callout = Font.system(size: 12.5, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let overline = Font.system(size: 9.5, weight: .semibold)
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
}

// MARK: - Surfaces

/// The app "page": white surface, hairline border and a soft drop shadow.
struct PanelSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) private var palette

    var body: some View {
        content()
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.separator, lineWidth: 1)
            )
            .shadow(color: palette.shadow, radius: 28, x: 0, y: 12)
            .padding(10)
    }
}

/// One-pixel rule, the main structural element of the layout.
struct Hairline: View {
    var inset: CGFloat = 0
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.separator)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

// MARK: - Motion

enum Motion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let content = Animation.easeInOut(duration: 0.18)
}
