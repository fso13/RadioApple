import AppKit
import SwiftUI

/// Sheet with the folders the app may read music from.
struct MusicSourcesView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var toasts: ToastCenter

    let onClose: () -> Void

    @Environment(\.palette) private var palette
    @State private var pendingRemove: MusicSource?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                PageHeading(
                    title: "Источники музыки",
                    subtitle: "Папки и файлы, к которым у RadioMac есть доступ"
                )
                Spacer()
                CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть", action: onClose)
            }

            if library.sources.isEmpty {
                EmptyStateView(
                    systemImage: "folder",
                    title: "Папок пока нет",
                    subtitle: "Добавьте папку с музыкой — приложение запомнит доступ и при следующем запуске.",
                    actionTitle: "Добавить папку"
                ) {
                    chooseFolder()
                }
                .frame(height: 200)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(library.sources) { source in
                            sourceRow(source)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
            }

            HStack(spacing: Space.m) {
                SecondaryButton(title: "Добавить папку", systemImage: "folder.badge.plus") {
                    chooseFolder()
                }
                SecondaryButton(title: "Добавить файлы", systemImage: "doc.badge.plus") {
                    chooseFiles()
                }
                if library.isScanning {
                    SecondaryButton(title: "Остановить", systemImage: "stop.circle") {
                        library.cancelScan()
                    }
                } else {
                    SecondaryButton(title: "Пересканировать", systemImage: "arrow.triangle.2.circlepath") {
                        library.rescan()
                    }
                }
                Spacer()
            }

            ToggleRow(
                title: "Подтягивать обложки и альбомы",
                subtitle: "Поиск в Apple Music и Deezer для треков без обложки. Файлы не изменяются.",
                isOn: library.autoEnrich
            ) { value in
                library.setAutoEnrich(value)
            }

            if library.isScanning || library.isEnriching {
                HStack(spacing: Space.s) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                    Text(library.scanStatus ?? library.enrichmentStatus ?? "Работаю…")
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            Text("Доступ выдаётся системным окном выбора и хранится в закладках macOS. Источник можно убрать в любой момент — файлы останутся на диске.")
                .font(Typeface.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Space.xxl + 2)
        .frame(width: 620, height: 560)
        .background(palette.surface)
        .alert(
            "Убрать источник?",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            presenting: pendingRemove
        ) { source in
            Button("Отмена", role: .cancel) { pendingRemove = nil }
            Button("Убрать", role: .destructive) {
                library.removeSource(id: source.id)
                toasts.show("«\(source.displayName)» убрана из источников", kind: .success)
                pendingRemove = nil
            }
        } message: { source in
            Text("Треки из «\(source.displayName)» исчезнут из библиотеки и плейлистов. Сами файлы останутся на диске.")
        }
    }

    private func sourceRow(_ source: MusicSource) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: source.isFolder ? "folder" : "music.note")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(Typeface.captionMedium)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(source.path)
                    .font(Typeface.monoSmall)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(source.path)
            }

            Spacer()

            Text("\(trackCount(for: source))")
                .font(Typeface.monoSmall)
                .foregroundStyle(palette.textTertiary)

            TextButton(title: "Убрать", tint: palette.red) {
                pendingRemove = source
            }
            .padding(.trailing, Space.scrollLane)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func trackCount(for source: MusicSource) -> Int {
        library.tracks.filter {
            $0.path == source.path || $0.path.hasPrefix(source.path + "/")
        }.count
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Добавить"
        panel.message = "Выберите папки с музыкой"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            var added = 0
            for url in urls {
                let summary = await library.addFolder(url)
                added += summary.added
            }
            library.flush()
            toasts.show(
                added > 0 ? "Добавлено треков: \(added)" : "Новых аудиофайлов не найдено",
                kind: added > 0 ? .success : .info
            )
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            let summary = await library.addFiles(urls)
            library.flush()
            toasts.show(
                summary.added > 0
                    ? "Добавлено треков: \(summary.added)"
                    : "Файлы не добавлены",
                kind: summary.added > 0 ? .success : .info
            )
        }
    }
}
