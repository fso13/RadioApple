import SwiftUI

/// Full-screen player: large artwork, live status, transport, volume and a way
/// into the equalizer. Mirrors the macOS panel's typography, scaled to a phone.
struct NowPlayingScreen: View {
    @ObservedObject var model: MainViewModel

    @EnvironmentObject private var player: RadioPlayerService
    @EnvironmentObject private var library: StationLibrary
    @EnvironmentObject private var equalizer: EqualizerService
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showEqualizer = false

    private var isLocal: Bool { player.localTrack != nil }

    private var artworkURL: String? {
        if let track = player.localTrack { return track.artworkURL }
        if let art = player.nowPlaying?.artworkURL { return art }
        return player.station?.logoURL
    }

    private var title: String {
        if let track = player.localTrack { return track.displayTitle }
        if let track = player.nowPlaying?.displayTitle { return track }
        return player.station?.name ?? "Ничего не играет"
    }

    private var subtitle: String {
        if let track = player.localTrack {
            return [track.displayArtist, track.displayAlbum]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        if let artist = player.nowPlaying?.displayArtist,
           artist != player.station?.name {
            if let station = player.station {
                return "\(artist) · \(station.name)"
            }
            return artist
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: Space.l)

            artwork
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 48 : Space.xxl)

            Spacer(minLength: Space.l)

            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.m) {
                    if isLocal {
                        Text("ЛОКАЛЬНЫЙ ФАЙЛ")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.4)
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        LiveIndicator()
                        if let station = player.station {
                            Text(station.genre.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(1.4)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                Text(title)
                    .font(.title.bold())
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xl)

            if let error = player.errorMessage,
               player.status == .error || player.status == .reconnecting {
                InlineErrorBanner(message: error) {
                    player.retryNow()
                }
                .padding(.top, Space.m)
            }

            if isLocal {
                progress
                    .padding(.horizontal, Space.xl)
                    .padding(.top, Space.l)
            } else {
                Spacer(minLength: Space.l)
            }

            transport
                .padding(.top, Space.l)

            footer
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.l)
                .padding(.bottom, Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.window.ignoresSafeArea())
        .sheet(isPresented: $showEqualizer) {
            EqualizerScreen()
                .presentationDetents([.large])
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "chevron.down", size: 14, help: "Свернуть") {
                dismiss()
            }

            Spacer()

            Menu {
                Button {
                    player.stop()
                    dismiss()
                } label: {
                    Label("Остановить", systemImage: "stop.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Ещё")
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.s)
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(urlString: artworkURL) {
                    ZStack {
                        palette.surfaceRaised
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 44, weight: .ultraLight))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .clipped()
            }
            .overlay {
                Rectangle()
                    .strokeBorder(palette.separator, lineWidth: 1)
            }
            .shadow(color: palette.shadow, radius: 22, x: 0, y: 10)
    }

    private var progress: some View {
        let duration = player.playbackDuration ?? 0
        let fraction = duration > 0 ? min(1, max(0, player.playbackElapsed / duration)) : 0

        return VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { fraction },
                    set: { player.seekLocal(toFraction: $0) }
                ),
                in: 0...1
            )
            .tint(palette.textPrimary)
            .disabled(duration <= 0)

            HStack {
                Text(TimeFormat.clock(player.playbackElapsed))
                Spacer()
                Text(TimeFormat.clock(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(palette.textTertiary)
        }
    }

    private var transport: some View {
        HStack(spacing: Space.xxl) {
            stepButton(systemName: "backward.fill", delta: -1, label: "Предыдущий")

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(palette.accentFill)
                        .frame(width: 68, height: 68)

                    if player.status == .loading {
                        ProgressView()
                            .tint(palette.onAccent)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Играть")

            stepButton(systemName: "forward.fill", delta: 1, label: "Следующий")
        }
    }

    private func stepButton(systemName: String, delta: Int, label: String) -> some View {
        Button {
            step(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(canStep(delta) ? palette.textPrimary : palette.textTertiary.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canStep(delta))
        .accessibilityLabel(label)
    }

    private var footer: some View {
        HStack(spacing: Space.l) {
            Button {
                showEqualizer = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.vertical.3")
                        .font(.subheadline.weight(.medium))
                    Text(equalizer.enabled ? "Эквалайзер · вкл" : "Эквалайзер")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(
                    equalizer.enabled ? palette.textPrimary : palette.textSecondary
                )
                .padding(.horizontal, Space.m)
                .frame(minHeight: 44)
                .overlay(
                    Capsule().strokeBorder(palette.separatorStrong, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            if let station = player.station, !isLocal, !dynamicTypeSize.isAccessibilitySize {
                Text(station.name)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Transport logic

    private var sequence: [RadioStation] {
        if let current = player.station,
           model.visible.contains(where: { $0.id == current.id }) {
            return model.visible
        }
        return library.stations
    }

    private func canStep(_ delta: Int) -> Bool {
        if player.localTrack != nil {
            return delta > 0 ? player.canPlayNextLocalTrack : player.canPlayPreviousLocalTrack
        }
        guard let current = player.station,
              let index = sequence.firstIndex(where: { $0.id == current.id })
        else { return false }
        return sequence.indices.contains(index + delta)
    }

    private func step(_ delta: Int) {
        if player.localTrack != nil {
            if delta > 0 {
                player.playNextLocalTrack()
            } else {
                player.playPreviousLocalTrack()
            }
            return
        }

        guard let current = player.station,
              let index = sequence.firstIndex(where: { $0.id == current.id })
        else { return }
        let next = index + delta
        guard sequence.indices.contains(next) else { return }
        player.play(sequence[next])
    }
}
