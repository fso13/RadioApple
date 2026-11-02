import SwiftUI

/// One row of the local music table: cover, title, album, duration, actions.
struct MusicTrackRow: View {
    let track: LocalTrack
    let isCurrent: Bool
    let isPlaying: Bool
    let isLoading: Bool
    let isInPlaylist: Bool
    let playlists: [MusicPlaylist]

    let onPlay: () -> Void
    let onEnrich: () -> Void
    let onEdit: () -> Void
    let onAddToPlaylist: (MusicPlaylist) -> Void
    let onRemoveFromPlaylist: () -> Void
    let onRevealInFinder: () -> Void
    let onDelete: () -> Void

    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Space.s) {
            marker
                .frame(width: 10)

            artwork
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(Typeface.headline)
                    .foregroundStyle(track.isMissing ? palette.textTertiary : palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(track.subtitle.isEmpty ? (track.isMissing ? "Файл не найден" : "Без исполнителя") : track.subtitle)
                    .font(Typeface.caption)
                    .foregroundStyle(track.isMissing ? palette.red : palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.displayAlbum ?? "—")
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 138, alignment: .leading)

            Text(track.durationText ?? "—")
                .font(Typeface.monoSmall)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 42, alignment: .trailing)

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
            .help("Действия с треком")
            .accessibilityLabel("Действия с треком")
        }
        .padding(.vertical, 5)
        .background((hovering || isCurrent) ? palette.surfaceHover : Color.clear)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .animation(Motion.hover, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(track.isMissing ? "Файл не найден" : "Включить трек")
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

    private var artwork: some View {
        ZStack {
            palette.surfaceRaised

            if track.isMissing {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            } else {
                RemoteImage(urlString: track.artworkURL) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .clipped()
        .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
        .opacity(track.isMissing ? 0.6 : 1)
    }

    private var accessibilityLabel: String {
        var parts = [track.displayTitle]
        if let artist = track.displayArtist { parts.append(artist) }
        if let album = track.displayAlbum { parts.append("альбом \(album)") }
        if let duration = track.durationText { parts.append(duration) }
        if isCurrent { parts.append(isPlaying ? "играет" : "выбран") }
        if track.isMissing { parts.append("файл не найден") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: onPlay) {
            Label("Играть", systemImage: "play")
        }

        Button(action: onEnrich) {
            Label("Обогатить из сети", systemImage: "sparkle.magnifyingglass")
        }

        Button(action: onEdit) {
            Label("Изменить метаданные…", systemImage: "pencil")
        }

        if !playlists.isEmpty {
            Menu {
                ForEach(playlists) { playlist in
                    Button(playlist.name) { onAddToPlaylist(playlist) }
                }
            } label: {
                Label("Добавить в плейлист", systemImage: "text.badge.plus")
            }
        }

        if isInPlaylist {
            Button(action: onRemoveFromPlaylist) {
                Label("Убрать из плейлиста", systemImage: "minus.circle")
            }
        }

        Divider()

        Button(action: onRevealInFinder) {
            Label("Показать в Finder", systemImage: "folder")
        }

        Button(role: .destructive, action: onDelete) {
            Label("Удалить из библиотеки", systemImage: "trash")
        }
    }
}
