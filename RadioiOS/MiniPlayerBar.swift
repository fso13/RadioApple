import SwiftUI

/// Compact transport docked above the tab bar: artwork, title, play/pause and
/// a tap target that opens the full player.
struct MiniPlayerBar: View {
    let onExpand: () -> Void

    @EnvironmentObject private var player: RadioPlayerService
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var title: String {
        if let track = player.localTrack { return track.displayTitle }
        if let track = player.nowPlaying?.displayTitle { return track }
        return player.station?.name ?? ""
    }

    private var subtitle: String {
        switch player.status {
        case .loading:
            return "Подключение…"
        case .reconnecting:
            return player.errorMessage ?? "Переподключение…"
        case .error:
            return player.errorMessage ?? "Ошибка воспроизведения"
        case .idle, .playing, .paused:
            break
        }

        if let track = player.localTrack {
            return [track.displayArtist, track.displayAlbum]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        if let artist = player.nowPlaying?.displayArtist,
           artist != player.station?.name {
            return artist
        }
        if let station = player.station {
            return station.genre
        }
        return ""
    }

    private var artworkURL: String? {
        if let track = player.localTrack { return track.artworkURL }
        if let art = player.nowPlaying?.artworkURL { return art }
        return player.station?.logoURL
    }

    var body: some View {
        HStack(spacing: Space.m) {
            Button(action: onExpand) {
                HStack(spacing: Space.m) {
                    artwork

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)

                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: Space.s)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Открыть плеер")

            Button {
                player.togglePlayPause()
            } label: {
                Group {
                    if player.status == .loading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Играть")

            Button(action: onExpand) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Открыть плеер")
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.separator, lineWidth: 1)
        )
        .shadow(color: palette.shadow, radius: 12, x: 0, y: 4)
    }

    private var artwork: some View {
        ZStack {
            palette.surfaceActive

            RemoteImage(urlString: artworkURL) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 40, height: 40)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(palette.separator, lineWidth: 1)
        )
    }
}

/// Docks the mini player above the tab bar and hides it while nothing plays.
private struct MiniPlayerInset: ViewModifier {
    let onExpand: () -> Void

    @EnvironmentObject private var player: RadioPlayerService

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.station != nil || player.localTrack != nil {
                MiniPlayerBar(onExpand: onExpand)
                    .padding(.horizontal, Space.s)
                    .padding(.bottom, Space.xxs)
            }
        }
    }
}

extension View {
    func miniPlayer(onExpand: @escaping () -> Void) -> some View {
        modifier(MiniPlayerInset(onExpand: onExpand))
    }
}
