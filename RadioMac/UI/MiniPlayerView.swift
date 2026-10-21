import SwiftUI

/// Compact menu-bar popover: artwork, transport, volume and quick station menu.
struct MiniPlayerView: View {
    @ObservedObject var player: RadioPlayerService
    @ObservedObject var library: StationLibrary
    @ObservedObject var theme: ThemeService
    let onOpenWindow: () -> Void

    @Environment(\.palette) private var palette
    @State private var volume: Double = 0.8

    var body: some View {
        ThemedRoot {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                artwork
                track
                transport
                volumeRow
                stationMenu
                footer
            }
            .padding(Space.l)
        }
        .frame(width: 320, height: 430)
        .onAppear { volume = player.volume }
        .onChange(of: player.volume) { _, value in
            if abs(volume - value) > 0.001 { volume = value }
        }
        .onChange(of: volume) { _, value in
            if abs(player.volume - value) > 0.001 { player.setVolume(value) }
        }
    }

    private var header: some View {
        HStack {
            Text("СЕЙЧАС")
                .font(Typeface.overline)
                .tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(player.status == .playing ? "LIVE" : player.status.rawValue.uppercased())
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(player.status == .error ? palette.red : palette.textTertiary)
        }
    }

    private var artwork: some View {
        ZStack {
            palette.surfaceRaised
            if let url = artworkURL {
                RemoteImage(urlString: url) { artworkPlaceholder }
            } else {
                artworkPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipped()
        .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { player.togglePlayPause() }
    }

    private var artworkPlaceholder: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }

    private var artworkURL: String? {
        if let artwork = player.nowPlaying?.artworkURL, !artwork.isEmpty { return artwork }
        guard let station = player.station, station.hasLogo else { return nil }
        return station.logoURL
    }

    private var track: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(player.station?.name ?? "Нет активной станции")
                .font(Typeface.body)
                .fontWeight(.medium)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(player.nowPlaying?.trayLine ?? (player.isPlaying ? "Играет" : "Выберите станцию"))
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
    }

    private var transport: some View {
        HStack(spacing: Space.m) {
            CircleIconButton(
                systemName: player.isPlaying ? "pause.fill" : "play.fill",
                size: 13,
                help: player.isPlaying ? "Пауза" : "Играть"
            ) {
                player.togglePlayPause()
            }
            TextButton(title: "Стоп", systemImage: "stop.fill") {
                player.stop()
            }
            Spacer()
            if player.status == .loading || player.status == .reconnecting {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "speaker.wave.1")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Slider(value: $volume, in: 0...1)
            Image(systemName: "speaker.wave.3")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var stationMenu: some View {
        Menu {
            ForEach(library.stations.prefix(20)) { station in
                Button(station.name) { player.play(station) }
            }
        } label: {
            HStack {
                Text("Быстрый выбор")
                    .font(Typeface.captionMedium)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.m)
            .frame(height: 30)
            .overlay(Rectangle().strokeBorder(palette.separatorStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var footer: some View {
        HStack {
            TextButton(title: "Открыть окно", systemImage: "macwindow", iconPosition: .trailing) {
                onOpenWindow()
            }
            Spacer()
            Text("RadioMac")
                .font(Typeface.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }
}
