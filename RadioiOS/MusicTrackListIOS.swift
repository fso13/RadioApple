import SwiftUI

/// One list of local tracks with playback and metadata actions.
///
/// `queue` is what the player will step through after a tap, so an album plays
/// in album order and a playlist in playlist order.
struct MusicTrackListIOS: View {
    let tracks: [LocalTrack]
    let queueTitle: String
    var playlist: MusicPlaylist?
    var numbered = false
    var isSelecting = false
    var selectedIDs: Set<String> = []
    var onToggleSelection: ((LocalTrack) -> Void)?
    let actions: MusicActions

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                MusicTrackRowIOS(
                    track: track,
                    number: numbered ? index + 1 : nil,
                    queue: tracks,
                    queueTitle: queueTitle,
                    playlist: playlist,
                    isSelecting: isSelecting,
                    isSelected: selectedIDs.contains(track.id),
                    onToggleSelection: { onToggleSelection?(track) },
                    actions: actions
                )

                Hairline(inset: 72)
            }
        }
    }
}

struct MusicTrackRowIOS: View {
    let track: LocalTrack
    var number: Int?
    let queue: [LocalTrack]
    let queueTitle: String
    var playlist: MusicPlaylist?
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: (() -> Void)?
    let actions: MusicActions

    @EnvironmentObject private var player: RadioPlayerService
    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCurrent: Bool { player.localTrack?.id == track.id }
    private var isPlaying: Bool { isCurrent && player.status == .playing }

    var body: some View {
        Button {
            if isSelecting {
                onToggleSelection?()
            } else {
                guard !track.isMissing else { return }
                actions.play(track, queue, queueTitle)
            }
        } label: {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(track.displayTitle), \(detail)"
                + (isSelecting ? (isSelected ? ", выбрано" : ", не выбрано") : "")
        )
        .accessibilityHint(selectionHint)
        .contextMenu {
            if !isSelecting { menu }
        }
    }

    private var content: some View {
        HStack(spacing: Space.m) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                    .frame(width: 28, height: 44)
            }

            if !isSelecting, let number, !dynamicTypeSize.isAccessibilitySize {
                Text(String(format: "%02d", number))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 22, alignment: .leading)
            } else if number == nil || isSelecting {
                artwork
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(track.isMissing ? palette.textTertiary : palette.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }

            Spacer(minLength: Space.s)

            if isCurrent {
                EqualizerBars(
                    isActive: isPlaying,
                    color: isPlaying ? palette.textPrimary : palette.textTertiary
                )
            }

            if let duration = track.duration {
                Text(TimeFormat.clock(duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: 58)
        .background(
            isSelected
                ? palette.surfaceActive
                : (isCurrent ? palette.surfaceActive.opacity(0.55) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var selectionHint: String {
        if isSelecting { return isSelected ? "Снять выбор" : "Выбрать" }
        return track.isMissing ? "Файл не найден" : "Играть"
    }

    private var detail: String {
        if track.isMissing { return "Файл не найден" }
        let parts = [track.displayArtist, track.displayAlbum].compactMap { $0 }
        return parts.isEmpty ? "Локальный файл" : parts.joined(separator: " · ")
    }

    private var artwork: some View {
        ZStack {
            palette.surfaceRaised

            RemoteImage(urlString: track.artworkURL) {
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 42, height: 42)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(palette.separator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            actions.play(track, queue, queueTitle)
        } label: {
            Label("Играть", systemImage: "play.fill")
        }
        .disabled(track.isMissing)

        Button {
            actions.editTrack(track)
        } label: {
            Label("Метаданные и обложка…", systemImage: "slider.horizontal.3")
        }

        Menu {
            ForEach(music.playlists) { target in
                Button(target.name) {
                    music.addTracks([track.id], to: target.id)
                }
            }
            if !music.playlists.isEmpty { Divider() }
            Button {
                actions.addToNewPlaylist(track)
            } label: {
                Label("Новый плейлист…", systemImage: "plus")
            }
        } label: {
            Label("Добавить в плейлист", systemImage: "text.badge.plus")
        }

        if let playlist {
            Button {
                actions.removeFromPlaylist(track, playlist)
            } label: {
                Label("Убрать из «\(playlist.name)»", systemImage: "minus.circle")
            }
        }

        Divider()

        Button(role: .destructive) {
            actions.deleteTrack(track)
        } label: {
            Label("Удалить из библиотеки", systemImage: "trash")
        }
    }
}
