import SwiftUI

/// Editorial wordmark: "RadioMac®" in ink, optionally with the glyph.
struct BrandMark: View {
    var fontSize: CGFloat = 11.5
    var showsGlyph: Bool = false

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 7) {
            if showsGlyph {
                BrandGlyph(size: fontSize + 2)
            }

            HStack(alignment: .top, spacing: 1) {
                Text("RadioMac")
                    .font(.system(size: fontSize, weight: .semibold))
                    .tracking(0.1)
                Text("®")
                    .font(.system(size: fontSize * 0.52, weight: .semibold))
                    .baselineOffset(fontSize * 0.42)
            }
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RadioMac")
        .accessibilityAddTraits(.isStaticText)
    }
}

/// The app glyph: emitter dot, broadcast arcs and a plus badge.
struct BrandGlyph: View {
    var size: CGFloat = 20

    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, canvasSize in
            let width = canvasSize.width
            let ink = palette.textPrimary
            let center = CGPoint(x: width * 0.42, y: width * 0.58)

            let dotRadius = width * 0.11
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - dotRadius,
                    y: center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(ink)
            )

            for (radius, start, sweep) in [(0.26, -2.3, 1.8), (0.40, -2.25, 1.7)] {
                var path = Path()
                let steps = 32
                for step in 0...steps {
                    let angle = start + sweep * Double(step) / Double(steps)
                    let point = CGPoint(
                        x: center.x + cos(angle) * width * radius,
                        y: center.y + sin(angle) * width * radius
                    )
                    if step == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(ink),
                    style: StrokeStyle(lineWidth: width * 0.085, lineCap: .round)
                )
            }

            let badge = width * 0.4
            let badgeCenter = CGPoint(x: width * 0.78, y: width * 0.78)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: badgeCenter.x - badge * 0.52,
                    y: badgeCenter.y - badge * 0.52,
                    width: badge * 1.04,
                    height: badge * 1.04
                )),
                with: .color(palette.surface)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: badgeCenter.x - badge * 0.42,
                    y: badgeCenter.y - badge * 0.42,
                    width: badge * 0.84,
                    height: badge * 0.84
                )),
                with: .color(ink)
            )

            let plusColor = palette.surface
            let arm = badge * 0.18
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: badgeCenter.x - arm, y: badgeCenter.y))
            horizontal.addLine(to: CGPoint(x: badgeCenter.x + arm, y: badgeCenter.y))
            var vertical = Path()
            vertical.move(to: CGPoint(x: badgeCenter.x, y: badgeCenter.y - arm))
            vertical.addLine(to: CGPoint(x: badgeCenter.x, y: badgeCenter.y + arm))
            let plusStyle = StrokeStyle(lineWidth: width * 0.07, lineCap: .round)
            context.stroke(horizontal, with: .color(plusColor), style: plusStyle)
            context.stroke(vertical, with: .color(plusColor), style: plusStyle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
