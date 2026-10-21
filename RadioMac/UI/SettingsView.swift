import SwiftUI

/// Settings page: appearance, behaviour, sound, library, help and about.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var theme: ThemeService
    @ObservedObject var equalizer: EqualizerService
    @ObservedObject var library: StationLibrary
    @ObservedObject var toasts: ToastCenter

    let onBack: () -> Void
    let onClose: () -> Void
    let onOpenEqualizer: () -> Void
    let onQuit: () -> Void

    @Environment(\.palette) private var palette

    @State private var showHelp = false
    @State private var expandedHelpID: String?
    @State private var launchAtStartup = false
    @State private var launchAtLoginSupported = true
    @State private var confirmRestore = false
    @State private var confirmQuit = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                PanelHeader(
                    onBack: {
                        if showHelp {
                            showHelp = false
                            expandedHelpID = nil
                        } else {
                            onBack()
                        }
                    },
                    trailing: {
                        CircleIconButton(
                            systemName: "xmark",
                            size: 11,
                            help: "Скрыть окно",
                            action: onClose
                        )
                    }
                )

                if showHelp {
                    HelpView(expandedID: $expandedHelpID)
                } else {
                    settingsContent
                }
            }
            .overlay(alignment: .bottom) {
                ToastOverlay(center: toasts)
            }
        }
        .task { loadLaunchAtLogin() }
        .alert("Восстановить каталог?", isPresented: $confirmRestore) {
            Button("Отмена", role: .cancel) {}
            Button("Восстановить") {
                library.restoreDefaults()
                toasts.show("Встроенные станции восстановлены", kind: .success)
            }
        } message: {
            Text("Встроенные станции вернутся к исходным. Ваши добавленные станции останутся.")
        }
        .alert("Завершить работу?", isPresented: $confirmQuit) {
            Button("Отмена", role: .cancel) {}
            Button("Завершить", role: .destructive, action: onQuit)
        } message: {
            Text("Приложение закроется полностью, включая иконку в меню-баре. Эфир остановится.")
        }
    }

    // MARK: - Content

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                PageHeading(
                    title: "Настройки",
                    subtitle: "Оформление, поведение и звук"
                )

                section("Оформление") {
                    themeChoices
                }

                section("Поведение") {
                    ToggleRow(
                        title: "Продолжать последнюю станцию",
                        subtitle: "Включать последний эфир при запуске",
                        isOn: settings.resumeLastStation,
                        onChange: { settings.setResumeLastStation($0) }
                    )
                    Hairline()
                    ToggleRow(
                        title: "Запуск при входе",
                        subtitle: launchAtLoginSupported
                            ? "Фоновый агент без значка в Dock"
                            : "Требуется macOS 13 или новее",
                        isOn: launchAtStartup,
                        isEnabled: launchAtLoginSupported,
                        onChange: { setAutoStart($0) }
                    )
                }

                section("Звук") {
                    SettingsRow(title: "Эквалайзер", subtitle: equalizerSubtitle) {
                        TextButton(title: "Настроить", systemImage: "arrow.right", iconPosition: .trailing) {
                            onOpenEqualizer()
                        }
                    }
                }

                section("Библиотека") {
                    SettingsRow(
                        title: "Каталог станций",
                        subtitle: "\(library.stations.count) станций · встроенные можно восстановить"
                    ) {
                        TextButton(title: "Сбросить") { confirmRestore = true }
                    }
                }

                section("Справка") {
                    SettingsRow(title: "Документация", subtitle: "Трей, потоки, жанры, горячие клавиши") {
                        TextButton(title: "Открыть", systemImage: "arrow.right", iconPosition: .trailing) {
                            showHelp = true
                            expandedHelpID = "basics"
                        }
                    }
                }

                section("О приложении") {
                    InfoRow(label: "Версия", value: version)
                    Hairline()
                    InfoRow(label: "Сборка", value: build)
                    Hairline()
                    InfoRow(label: "Станций в библиотеке", value: "\(library.stations.count)")
                    Hairline()
                    HStack {
                        Text("RadioMac® · интернет-радио в меню-баре")
                            .font(Typeface.caption)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, Space.m)
                }

                VStack(alignment: .leading, spacing: Space.m) {
                    DestructiveButton(
                        title: "Завершить RadioMac",
                        systemImage: "power",
                        fullWidth: true
                    ) {
                        confirmQuit = true
                    }
                }
            }
            .padding(Space.xxl)
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Typeface.section)
                .foregroundStyle(palette.textPrimary)
                .padding(.bottom, Space.s - 2)
            Hairline()
            content()
        }
    }

    private var themeChoices: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xl) {
                ForEach(ThemeService.Preference.allCases) { preference in
                    let isSelected = theme.preference == preference
                    Button {
                        theme.setPreference(preference)
                    } label: {
                        VStack(spacing: 4) {
                            Text(preference.label)
                                .font(isSelected ? Typeface.captionMedium : Typeface.caption)
                                .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                            Rectangle()
                                .fill(isSelected ? palette.textPrimary : Color.clear)
                                .frame(height: 1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                Spacer()
            }
            .padding(.vertical, Space.m)

            Text(theme.preference.detail)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, Space.m)
        }
    }

    // MARK: - State

    private var equalizerSubtitle: String {
        guard equalizer.isSupported else { return "Недоступен на этом Mac" }
        return equalizer.enabled
            ? "Включён · \(equalizer.preset.label)"
            : "Выключен"
    }

    private func loadLaunchAtLogin() {
        let status = LaunchAtLogin.status()
        launchAtLoginSupported = status.supported
        launchAtStartup = status.enabled
    }

    private func setAutoStart(_ enabled: Bool) {
        let result = LaunchAtLogin.set(enabled: enabled)
        guard result.ok else {
            toasts.show(result.error ?? "Не удалось изменить автозапуск", kind: .error)
            let current = LaunchAtLogin.status()
            launchAtStartup = current.enabled
            launchAtLoginSupported = current.supported
            return
        }
        settings.setAutoStartEnabled(result.enabled)
        launchAtStartup = result.enabled
        launchAtLoginSupported = result.supported
    }
}
