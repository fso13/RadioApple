import SwiftUI

/// Full-width transport bar at the bottom of the panel.
struct PlayerBar: View {
    @ObservedObject var player: RadioPlayerService
    @ObservedObject var equalizer: EqualizerService
    @ObservedObject var sleepTimer: SleepTimerService

    let onOpenEqualizer: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let canPrevious: Bool
    let canNext: Bool
    let canPlay: Bool
    let onPlayFallback: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Hairline()

            HStack(spacing: Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typeface.headline)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(Typeface.caption)
                        .foregroundStyle(player.status == .error ? palette.red : palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                transport

                HStack(spacing: Space.s + 2) {
                    sleepMenu
                    CircleIconButton(
                        systemName: "slider.vertical.3",
                        size: 11,
                        help: "Эквалайзер",
                        isActive: equalizer.enabled,
                        action: onOpenEqualizer
                    )

                    Image(systemName: "speaker.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)

                    Slider(
                        value: Binding(
                            get: { player.volume },
                            set: { player.setVolume($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    .tint(palette.accentFill)
                    .frame(width: 76)
                    .accessibilityLabel("Громкость")

                    if player.status == .error {
                        CircleIconButton(
                            systemName: "arrow.clockwise",
                            size: 10,
                            help: "Повторить",
                            action: player.retryNow
                        )
                    } else if player.status == .reconnecting {
                        Text("RECONNECT")
                            .font(Typeface.monoSmall)
                            .tracking(1.1)
                            .foregroundStyle(palette.textSecondary)
                    } else if player.isPlaying {
                        LiveIndicator()
                    } else {
                        Text("OFF AIR")
                            .font(Typeface.monoSmall)
                            .tracking(1.1)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, Space.xl)
            .frame(height: 68)
        }
    }

    private var sleepMenu: some View {
        Menu {
            ForEach(SleepTimerService.Option.allCases) { option in
                Button(option.title) { sleepTimer.start(minutes: option.rawValue) }
            }
            if sleepTimer.isActive {
                Divider()
                Button("Отменить таймер") { sleepTimer.cancel() }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 10, weight: .medium))
                if sleepTimer.isActive {
                    Text(sleepTimer.remainingText)
                        .font(Typeface.monoSmall)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(sleepTimer.isActive ? palette.textPrimary : palette.textTertiary)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(sleepTimer.isActive ? "Таймер сна: \(sleepTimer.remainingText)" : "Таймер сна")
        .accessibilityLabel(sleepTimer.isActive ? "Таймер сна, осталось \(sleepTimer.remainingText)" : "Таймер сна")
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: Space.l + 2) {
            CircleIconButton(
                systemName: "stop.fill",
                size: 8,
                tint: player.isActive ? palette.textSecondary : palette.textTertiary.opacity(0.45),
                help: "Стоп",
                action: player.stop
            )
            .disabled(!player.isActive)

            CircleIconButton(
                systemName: "backward.end.fill",
                size: 10,
                tint: canPrevious ? palette.textPrimary : palette.textTertiary.opacity(0.45),
                help: "Предыдущая станция",
                action: onPrevious
            )
            .disabled(!canPrevious)

            playButton

            CircleIconButton(
                systemName: "forward.end.fill",
                size: 10,
                tint: canNext ? palette.textPrimary : palette.textTertiary.opacity(0.45),
                help: "Следующая станция",
                action: onNext
            )
            .disabled(!canNext)
        }
    }

    private var playButton: some View {
        Button {
            if player.station == nil {
                onPlayFallback()
            } else {
                player.togglePlayPause()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(palette.accentFill.opacity(canPlay ? 1 : 0.3))
                    .frame(width: 32, height: 32)

                if player.status == .loading || player.status == .reconnecting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(palette.onAccent)
                        .scaleEffect(0.55)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canPlay)
        .help(player.isPlaying ? "Пауза" : "Играть")
        .accessibilityLabel(player.isPlaying ? "Пауза" : "Играть")
    }

    // MARK: - Content

    private var title: String {
        if let track = player.nowPlaying { return track.displayTitle }
        return player.station?.name ?? "Ничего не играет"
    }

    private var subtitle: String {
        if player.status == .reconnecting {
            return player.errorMessage ?? "Переподключение…"
        }
        if player.status == .error {
            return player.errorMessage ?? "Не удалось открыть поток"
        }
        if let track = player.nowPlaying {
            var parts: [String] = []
            if let artist = track.displayArtist { parts.append(artist) }
            if let station = player.station { parts.append(station.name) }
            return parts.joined(separator: " — ")
        }
        if player.status == .loading { return "Подключение…" }
        if player.isActive { return "Нет данных о треке" }
        return player.station?.genre ?? "Выберите станцию из списка"
    }
}
