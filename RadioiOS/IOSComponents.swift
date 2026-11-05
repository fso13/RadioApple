import SwiftUI

/// Editorial page header: small overline on top, large title below, actions on
/// the right. Replaces the navigation bar so the app keeps one typographic
/// system instead of the system chrome.
struct ScreenHeader<Trailing: View>: View {
    let overline: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(overline.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(palette.textTertiary)
                }

                Spacer(minLength: Space.s)

                trailing()
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !dynamicTypeSize.isAccessibilitySize {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
        .padding(.bottom, Space.m)
    }
}

/// Hairline search field used on the radio and music screens.
struct SearchFieldIOS: View {
    @Binding var text: String
    var placeholder: String

    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isFocused ? palette.textPrimary : palette.textTertiary)

                TextField(
                    "",
                    text: $text,
                    prompt: Text(placeholder).foregroundColor(palette.textTertiary)
                )
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(palette.textPrimary)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { isFocused = false }

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .frame(minHeight: 44)

            Rectangle()
                .fill(isFocused ? palette.textPrimary : palette.separator)
                .frame(height: 1)
        }
        .padding(.horizontal, Space.l)
    }
}

/// Understated filter entry: label over a hairline that inks itself when active.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                    .lineLimit(1)

                Rectangle()
                    .fill(isSelected ? palette.textPrimary : Color.clear)
                    .frame(height: 1)
            }
            .frame(minHeight: 44)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Stream error with a manual retry, shown above the station list.
struct InlineErrorBanner: View {
    let message: String
    let retry: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.red)

            Text(message)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            Spacer(minLength: Space.s)

            Button("Повторить", action: retry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(palette.surfaceRaised)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Uppercase section label used inside settings and sheets.
struct SectionLabel: View {
    let title: String

    @Environment(\.palette) private var palette

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(palette.textTertiary)
    }
}

enum TimeFormat {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
