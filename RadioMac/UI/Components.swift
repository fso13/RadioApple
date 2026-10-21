import AppKit
import SwiftUI

// MARK: - Window drag handle

/// Native drag handle for the frameless panel's header.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Header

/// Slim header: brand or back button on the left, actions on the right.
struct PanelHeader<Trailing: View>: View {
    private let onBack: (() -> Void)?
    private let showBrand: Bool
    private let trailing: Trailing

    @Environment(\.palette) private var palette

    init(
        onBack: (() -> Void)? = nil,
        showBrand: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.onBack = onBack
        self.showBrand = showBrand
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            WindowDragArea()

            HStack(spacing: Space.s) {
                if let onBack {
                    CircleIconButton(
                        systemName: "arrow.left",
                        size: 12,
                        help: "Назад",
                        action: onBack
                    )
                } else if showBrand {
                    BrandMark(fontSize: 11.5)
                }

                Spacer(minLength: Space.s)

                trailing
            }
            .padding(.horizontal, Space.xl)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The hamburger menu from the reference, backed by a native NSMenu.
struct PanelMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? palette.textPrimary : palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(hovering ? palette.surfaceHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Меню")
        .accessibilityLabel("Меню")
    }
}

// MARK: - Buttons

/// Ghost icon button used in headers and toolbars.
struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    var tint: Color?
    var help: String?
    var isActive: Bool = false
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(hovering ? palette.surfaceHover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help(help ?? "")
        .accessibilityLabel(help ?? systemName)
    }

    private var iconColor: Color {
        if let tint { return tint }
        if isActive { return palette.accent }
        return hovering ? palette.textPrimary : palette.textSecondary
    }
}

/// Solid ink button — the one strong action on a page.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var fullWidth: Bool = false
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(Typeface.captionMedium)
            }
            .foregroundStyle(palette.onAccent.opacity(isEnabled ? 1 : 0.6))
            .padding(.horizontal, Space.m + 2)
            .frame(height: 30)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(palette.accentFill.opacity(isEnabled ? (hovering ? 0.82 : 1) : 0.3))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 && isEnabled }
        .animation(Motion.hover, value: hovering)
    }
}

/// Outlined neutral button.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var fullWidth: Bool = false
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(Typeface.captionMedium)
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.m + 2)
            .frame(height: 30)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(hovering ? palette.surfaceHover : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .strokeBorder(palette.separatorStrong, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

/// Inline text action, e.g. "Настроить →" or "Сбросить".
struct TextButton: View {
    enum IconPosition {
        case leading
        case trailing
    }

    let title: String
    var systemImage: String?
    var iconPosition: IconPosition = .leading
    var tint: Color?
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if iconPosition == .leading, let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .medium))
                }
                Text(title).font(Typeface.captionMedium)
                if iconPosition == .trailing, let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundStyle((tint ?? palette.textPrimary).opacity(hovering ? 0.6 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Destructive inline action.
struct DestructiveButton: View {
    let title: String
    var systemImage: String?
    var fullWidth: Bool = false
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(Typeface.captionMedium)
            }
            .foregroundStyle(palette.red.opacity(hovering ? 0.7 : 1))
            .padding(.horizontal, Space.m + 2)
            .frame(height: 30)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: - Search

/// Borderless search line with a hairline underline.
struct SearchLine: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    @Environment(\.palette) private var palette
    @State private var hoveringClear = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isFocused ? palette.textPrimary : palette.textTertiary)

                TextField(
                    "",
                    text: $text,
                    prompt: Text("Поиск станций").foregroundColor(palette.textTertiary)
                )
                .textFieldStyle(.plain)
                .font(Typeface.callout)
                .foregroundStyle(palette.textPrimary)
                .focused($isFocused)

                if text.isEmpty {
                    Text("⌘F")
                        .font(Typeface.monoSmall)
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityHidden(true)
                } else {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(hoveringClear ? palette.textPrimary : palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveringClear = $0 }
                    .help("Очистить поиск")
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .frame(height: 26)

            Rectangle()
                .fill(isFocused ? palette.textPrimary : palette.separator)
                .frame(height: 1)
                .animation(Motion.hover, value: isFocused)
        }
    }
}

// MARK: - Navigation

/// Large editorial genre entry.
struct NavItem: View {
    let label: String
    let isSelected: Bool
    var isPlaying: Bool = false
    let action: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Text(label)
                    .font(isSelected ? Typeface.navActive : Typeface.nav)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if isSelected && isPlaying {
                    EqualizerBars(isActive: true, color: palette.textPrimary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var color: Color {
        if isSelected { return palette.textPrimary }
        return hovering ? palette.textSecondary : palette.textTertiary.opacity(0.55)
    }
}

// MARK: - Page heading

struct PageHeading: View {
    let title: String
    var subtitle: String?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs + 2) {
            Text(title)
                .font(Typeface.pageTitle)
                .foregroundStyle(palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(Typeface.callout)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}

// MARK: - Settings rows

struct SettingsRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    @Environment(\.palette) private var palette

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typeface.body)
                    .foregroundStyle(palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Space.s)

            trailing
        }
        .padding(.vertical, Space.m - 1)
        .frame(minHeight: 48)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    let isOn: Bool
    var isEnabled: Bool = true
    let onChange: @MainActor (Bool) -> Void

    @Environment(\.palette) private var palette
    @State private var value: Bool

    init(
        title: String,
        subtitle: String? = nil,
        isOn: Bool,
        isEnabled: Bool = true,
        onChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.onChange = onChange
        _value = State(initialValue: isOn)
    }

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $value)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(palette.accentFill)
                .controlSize(.small)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
                .onChange(of: value) { _, newValue in
                    onChange(newValue)
                }
                .onChange(of: isOn) { _, newValue in
                    if value != newValue { value = newValue }
                }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            Text(label)
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(Typeface.mono)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(value)
        }
        .padding(.vertical, Space.m - 2)
    }
}

// MARK: - State views

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.textTertiary)

            VStack(spacing: Space.xs) {
                Text(title)
                    .font(Typeface.section)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(Typeface.callout)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let actionTitle, let action {
                SecondaryButton(title: actionTitle, action: action)
                    .padding(.top, Space.xs)
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Equalizer bars

/// Three bars: the "now playing" mark, also used next to the active genre.
struct EqualizerBars: View {
    var isActive: Bool
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !isActive || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = sin(time * 3.2 + Double(index) * 1.4)
                    let height = isActive ? 5 + (phase + 1) * 3 : 4 + Double(index) * 2
                    Rectangle()
                        .fill(color)
                        .frame(width: 2, height: height)
                }
            }
            .frame(width: 10, height: 12)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Live indicator

struct LiveIndicator: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(palette.red)
                .frame(width: 4, height: 4)
            Text("LIVE")
                .font(Typeface.monoSmall)
                .tracking(1.1)
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityLabel("Прямой эфир")
    }
}

// MARK: - Toast

final class ToastCenter: ObservableObject {
    enum Kind {
        case info
        case success
        case error
    }

    struct Toast: Equatable {
        let message: String
        let kind: Kind
    }

    @Published private(set) var toast: Toast?
    private var dismissWorkItem: DispatchWorkItem?

    func show(_ message: String, kind: Kind = .info) {
        dismissWorkItem?.cancel()
        withAnimation(Motion.content) { toast = Toast(message: message, kind: kind) }

        let item = DispatchWorkItem { [weak self] in
            withAnimation(Motion.content) { self?.toast = nil }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: item)
    }
}

struct ToastOverlay: View {
    @ObservedObject var center: ToastCenter

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let toast = center.toast {
                HStack(spacing: Space.s) {
                    Image(systemName: icon(for: toast.kind))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color(for: toast.kind))
                    Text(toast.message)
                        .font(Typeface.captionMedium)
                        .foregroundStyle(palette.onAccent)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(palette.accentFill)
                )
                .padding(.bottom, 92)
                .transition(
                    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
                )
            }
        }
        .animation(Motion.content, value: center.toast)
        .allowsHitTesting(false)
    }

    private func icon(for kind: ToastCenter.Kind) -> String {
        switch kind {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func color(for kind: ToastCenter.Kind) -> Color {
        switch kind {
        case .info, .success: return palette.onAccent
        case .error: return palette.red
        }
    }
}

// MARK: - Flow layout

/// Wrapping layout for genre choices.
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.s
    var lineSpacing: CGFloat = Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                rowWidth = 0
                rowHeight = 0
            }
            if rowWidth > 0 { rowWidth += spacing }
            rowWidth += size.width
            rowHeight = max(rowHeight, size.height)
        }

        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
