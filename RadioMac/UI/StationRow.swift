import SwiftUI

/// One row of the station table: marker, number, name, genre, favourite, actions.
struct StationRow: View {
    let station: RadioStation
    let index: Int
    let isSelected: Bool
    let isCurrent: Bool
    let isPlaying: Bool
    let isLoading: Bool

    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    private var secondaryLine: String {
        if station.hasComment, let comment = station.comment { return comment }
        if let host = URL(string: station.url)?.host { return host }
        return "—"
    }

    var body: some View {
        HStack(spacing: Space.s) {
            marker
                .frame(width: 10)

            Text("\(index + 1)")
                .font(Typeface.caption)
                .monospacedDigit()
                .foregroundStyle(palette.textTertiary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(Typeface.headline)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(secondaryLine)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(station.genre)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .frame(width: 82, alignment: .leading)

            Button(action: onToggleFavorite) {
                Image(systemName: station.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(station.isFavorite ? palette.textPrimary : palette.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(station.isFavorite ? "Убрать из избранного" : "В избранное")
            .accessibilityLabel(station.isFavorite ? "Убрать из избранного" : "В избранное")

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering ? palette.textPrimary : palette.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Действия со станцией")
            .accessibilityLabel("Действия со станцией")
        }
        .padding(.vertical, 7)
        .background(
            (hovering || isSelected) ? palette.surfaceHover : Color.clear
        )
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .animation(Motion.hover, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Включить станцию")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onPlay)
    }

    @ViewBuilder
    private var marker: some View {
        if isCurrent {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
            } else {
                EqualizerBars(isActive: isPlaying, color: palette.textPrimary)
            }
        } else {
            Color.clear
        }
    }

    private var accessibilityLabel: String {
        var parts = [station.name, station.genre]
        if let comment = station.comment, station.hasComment { parts.append(comment) }
        if let group = station.group, !group.isEmpty { parts.append("группа \(group)") }
        if station.isFavorite { parts.append("в избранном") }
        if isCurrent { parts.append(isPlaying ? "играет" : "выбрана") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onPlay) {
            Label("Играть", systemImage: "play")
        }
        Button(action: onToggleFavorite) {
            Label(
                station.isFavorite ? "Убрать из избранного" : "В избранное",
                systemImage: station.isFavorite ? "star.slash" : "star"
            )
        }
        Button(action: onEdit) {
            Label("Изменить", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Удалить", systemImage: "trash")
        }
    }
}
