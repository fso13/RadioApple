import SwiftUI

/// Settings that matter on a phone: appearance, resume behaviour, the
/// equalizer, the station library and the build stamp.
struct SettingsScreen: View {
    @Binding var showPlayer: Bool

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var theme: ThemeService
    @EnvironmentObject private var equalizer: EqualizerService
    @EnvironmentObject private var library: StationLibrary
    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.palette) private var palette

    @State private var showEqualizer = false
    @State private var confirmRestore = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(overline: "RadioMac", title: "Настройки") {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    appearance
                    behaviour
                    sound
                    musicSettings
                    stations
                    about
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xxl)
            }
        }
        .background(palette.window)
        .miniPlayer { showPlayer = true }
        .sheet(isPresented: $showEqualizer) {
            EqualizerScreen()
                .presentationDetents([.large])
        }
        .confirmationDialog(
            "Вернуть стандартные станции?",
            isPresented: $confirmRestore
        ) {
            Button("Вернуть", role: .destructive) {
                library.restoreDefaults()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Свои станции и избранное сохранятся. Стандартные вернутся в исходном виде.")
        }
    }

    // MARK: - Sections

    private var appearance: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "Оформление")

            Picker(
                "Тема",
                selection: Binding(
                    get: { theme.preference },
                    set: { theme.setPreference($0) }
                )
            ) {
                ForEach(ThemeService.Preference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .tint(palette.textPrimary)
        }
    }

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "Поведение")

            Toggle(
                isOn: Binding(
                    get: { settings.resumeLastStation },
                    set: { settings.setResumeLastStation($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Продолжать последнюю станцию")
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                    Text("При запуске включать станцию, которая играла в прошлый раз")
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .tint(palette.textPrimary)
            .padding(.vertical, Space.s)

            Hairline()
        }
    }

    private var sound: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "Звук")

            Button {
                showEqualizer = true
            } label: {
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Эквалайзер")
                            .font(.subheadline)
                            .foregroundStyle(palette.textPrimary)
                        Text(equalizer.enabled ? equalizer.preset.label : "Выключен")
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Hairline()
        }
    }

    private var musicSettings: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "Музыка")

            Toggle(
                isOn: Binding(
                    get: { music.autoEnrich },
                    set: { music.setAutoEnrich($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Обогащать метаданные автоматически")
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                    Text("Обложки, альбомы, годы и жанры из Apple Music и Deezer")
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .tint(palette.textPrimary)
            .padding(.vertical, Space.s)

            Hairline()

            Button {
                music.startEnrichment()
            } label: {
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Обогатить всю библиотеку")
                            .font(.subheadline)
                            .foregroundStyle(palette.textPrimary)
                        Text(
                            music.isEnriching
                                ? (music.enrichmentStatus ?? "Обогащаю…")
                                : MusicCount.tracks(music.tracks.count)
                        )
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    }

                    Spacer()

                    if music.isEnriching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(music.isEnriching)

            Hairline()
        }
    }

    private var stations: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "Библиотека")

            HStack {
                Text("Станций в библиотеке")
                    .font(.subheadline)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(library.stations.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.vertical, Space.s)

            Hairline()

            HStack {
                Text("Локальных треков")
                    .font(.subheadline)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(music.tracks.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.vertical, Space.s)

            Hairline()

            Button {
                confirmRestore = true
            } label: {
                HStack {
                    Text("Вернуть стандартные станции")
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Hairline()

            Text("Импортированную музыку можно положить и через «Файлы»: RadioMac → Music. Файлы копируются в контейнер приложения.")
                .font(.caption)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.xs)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "О приложении")

            HStack(alignment: .firstTextBaseline) {
                BrandMark(fontSize: 18, showsGlyph: true)
                Spacer()
                Text("\(version) (\(build))")
                    .font(.caption.monospaced())
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.vertical, Space.s)

            Text(
                "Плеер интернет-радио для iPhone. Эфир, каталог Radio Browser и локальные "
                    + "файлы. Собран из того же ядра, что и RadioMac для macOS."
            )
                .font(.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Copyright © 2026 Dmitry Rudenko")
                .font(.caption2)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.xs)
        }
    }
}
