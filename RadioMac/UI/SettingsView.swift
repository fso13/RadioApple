import AppKit
import SwiftUI

/// Settings page: appearance, behaviour, sound, library, help and about.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var theme: ThemeService
    @ObservedObject var equalizer: EqualizerService
    @ObservedObject var player: RadioPlayerService
    @ObservedObject var alarm: AlarmService
    @ObservedObject var diagnostics: DiagnosticsService
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
    @State private var showDiagnostics = false

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
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView(diagnostics: diagnostics) {
                showDiagnostics = false
            }
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

                section("Будильник") {
                    ToggleRow(
                        title: "Включён",
                        subtitle: alarmSubtitle,
                        isOn: alarm.settings.enabled,
                        onChange: { alarm.setEnabled($0) }
                    )
                    Hairline()
                    alarmTimeRow
                    Hairline()
                    alarmWeekdayRow
                    Hairline()
                    alarmStationRow
                    Hairline()
                    InfoRow(label: "Следующий", value: alarmNextText)

                    Text("Будильник работает, пока RadioMac запущен. После сна может сработать с задержкой до 10 минут.")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Space.m)

                    if alarm.notificationDenied {
                        Text("Уведомления запрещены в системных настройках. Будильник всё равно сработает, пока приложение запущено.")
                            .font(Typeface.caption)
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Space.m)
                    }
                }

                section("Звук") {
                    SettingsRow(title: "Эквалайзер", subtitle: equalizerSubtitle) {
                        TextButton(title: "Настроить", systemImage: "arrow.right", iconPosition: .trailing) {
                            onOpenEqualizer()
                        }
                    }
                }

                section("Поток") {
                    InfoRow(
                        label: "Станция",
                        value: player.station?.name ?? "Нет активного потока"
                    )
                    Hairline()
                    InfoRow(label: "Статус", value: playerStatusText)
                    Hairline()
                    InfoRow(label: "Кодек", value: player.streamInfo?.codec ?? "—")
                    Hairline()
                    InfoRow(label: "Битрейт", value: player.streamInfo?.bitrateText ?? "—")
                    Hairline()
                    InfoRow(label: "Частота", value: player.streamInfo?.sampleRateText ?? "—")
                    Hairline()
                    InfoRow(label: "Каналы", value: player.streamInfo?.channelsText ?? "—")
                    Hairline()
                    InfoRow(label: "Буфер", value: player.streamInfo?.bufferText ?? "—")
                    Hairline()
                    InfoRow(label: "Сервер", value: streamServer)
                    HStack(spacing: Space.l) {
                        TextButton(title: "Обновить", systemImage: "arrow.clockwise") {
                            player.refreshStreamInfo()
                        }
                        TextButton(
                            title: "Скопировать диагностику",
                            systemImage: "doc.on.doc"
                        ) {
                            copyDiagnostics()
                        }
                        Spacer()
                    }
                    .padding(.vertical, Space.m)
                }

                section("Диагностика") {
                    ToggleRow(
                        title: "Локальный журнал",
                        subtitle: diagnostics.isEnabled
                            ? "Пишет события в контейнер приложения"
                            : "Выключен · данные никуда не отправляются",
                        isOn: diagnostics.isEnabled,
                        onChange: { diagnostics.setEnabled($0) }
                    )
                    Hairline()
                    HStack(spacing: Space.l) {
                        TextButton(
                            title: "Открыть журнал",
                            systemImage: "doc.text.magnifyingglass"
                        ) {
                            showDiagnostics = true
                        }
                        TextButton(title: "Показать в Finder", systemImage: "folder") {
                            revealDiagnostics()
                        }
                        Spacer()
                    }
                    .padding(.vertical, Space.m)

                    if let crash = diagnostics.lastCrashDate {
                        Text("Прошлый сеанс завершился аварийно: \(crashText(crash)).")
                            .font(Typeface.caption)
                            .foregroundStyle(palette.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Space.m)
                    }

                    Text("Журнал хранится только на этом Mac. URL обрезаются до домена, данные никуда не отправляются.")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Space.m)
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

    private func crashText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter.string(from: date)
    }

    private func revealDiagnostics() {
        let target = diagnostics.hasLog
            ? diagnostics.logURL
            : diagnostics.logURL.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private var alarmSubtitle: String {
        guard alarm.settings.enabled else {
            return "Разбудит радио в выбранное время"
        }
        if alarm.settings.weekdays.isEmpty {
            return "Выберите хотя бы один день"
        }
        return "Плавное нарастание за \(alarm.settings.fadeInSeconds) секунд"
    }

    private var alarmNextText: String {
        guard alarm.settings.enabled else { return "Выключен" }
        guard !alarm.settings.weekdays.isEmpty else { return "Выберите дни" }
        guard let next = alarm.nextFireDate else { return "Нет ближайшего запуска" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM, HH:mm"
        return formatter.string(from: next)
    }

    private var alarmStationName: String {
        if let id = alarm.settings.stationID, let station = library.byID(id) {
            return station.name
        }
        return "Последняя играющая"
    }

    private var alarmTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents(
                    [.year, .month, .day],
                    from: Date()
                )
                components.hour = alarm.settings.hour
                components.minute = alarm.settings.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                alarm.setTime(
                    hour: components.hour ?? 7,
                    minute: components.minute ?? 30
                )
            }
        )
    }

    private var alarmTimeRow: some View {
        HStack {
            Text("Время")
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            DatePicker(
                "",
                selection: alarmTimeBinding,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 96)
        }
        .padding(.vertical, Space.m - 2)
        .disabled(!alarm.settings.enabled)
        .opacity(alarm.settings.enabled ? 1 : 0.5)
    }

    private var alarmWeekdayRow: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("ДНИ")
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            HStack(spacing: Space.l) {
                ForEach(AlarmSettings.weekdayOrder, id: \.self) { weekday in
                    let selected = alarm.settings.weekdays.contains(weekday)
                    Button {
                        alarm.toggleWeekday(weekday)
                    } label: {
                        VStack(spacing: 4) {
                            Text(AlarmSettings.shortLabel(for: weekday))
                                .font(selected ? Typeface.captionMedium : Typeface.caption)
                                .foregroundStyle(
                                    selected ? palette.textPrimary : palette.textTertiary
                                )
                            Rectangle()
                                .fill(selected ? palette.textPrimary : Color.clear)
                                .frame(height: 1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!alarm.settings.enabled)
                    .accessibilityLabel(AlarmSettings.fullLabel(for: weekday))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Space.m)
        .opacity(alarm.settings.enabled ? 1 : 0.5)
    }

    private var alarmStationRow: some View {
        HStack {
            Text("Станция")
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Menu {
                Button("Последняя играющая") {
                    alarm.setStation(nil)
                }
                Divider()
                ForEach(library.stations) { station in
                    Button(station.name) {
                        alarm.setStation(station.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(alarmStationName)
                        .font(Typeface.captionMedium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(palette.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!alarm.settings.enabled)
        }
        .padding(.vertical, Space.m - 2)
        .opacity(alarm.settings.enabled ? 1 : 0.5)
    }

    private var playerStatusText: String {
        switch player.status {
        case .idle: return "Простой"
        case .loading: return "Подключение"
        case .playing: return "Эфир"
        case .paused: return "Пауза"
        case .error: return "Ошибка"
        }
    }

    private var streamServer: String {
        guard let station = player.station,
              let host = URL(string: station.url)?.host
        else { return "—" }
        return host
    }

    private func copyDiagnostics() {
        let info = player.streamInfo
        let station = player.station
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let lines = [
            "RadioMac \(version) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Дата: \(timestamp)",
            "",
            "Станция: \(station?.name ?? "—")",
            "URL: \(station?.url ?? "—")",
            "Сервер: \(streamServer)",
            "Статус: \(playerStatusText)",
            "Кодек: \(info?.codec ?? "—")",
            "Битрейт: \(info?.bitrateText ?? "—")",
            "Частота: \(info?.sampleRateText ?? "—")",
            "Каналы: \(info?.channelsText ?? "—")",
            "Буфер: \(info?.bufferText ?? "—")",
            "Эквалайзер: \(equalizerSubtitle)",
            "Ошибка: \(player.errorMessage ?? "—")",
        ]

        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(
            lines.joined(separator: "\n"),
            forType: .string
        )
        toasts.show(
            copied ? "Диагностика скопирована" : "Не удалось скопировать диагностику",
            kind: copied ? .success : .error
        )
    }

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
