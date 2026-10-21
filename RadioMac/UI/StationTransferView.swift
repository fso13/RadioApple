import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Import/export of the station library in JSON, M3U and OPML.
struct StationTransferView: View {
    @ObservedObject var library: StationLibrary
    @ObservedObject var toasts: ToastCenter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var mode: StationImportMode = .merge
    @State private var format: StationTransferFormat = .json
    @State private var result: StationImportResult?
    @State private var isTargeted = false

    var body: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                modePicker
                formatPicker
                actions
                if let result {
                    Text(
                        "Добавлено: \(result.added) · пропущено: \(result.skipped) · избранное: \(result.favoritesUpdated)"
                    )
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                }
                dropZone
            }
            .padding(Space.xxl)
        }
        .frame(width: 660, height: 470)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.accent, lineWidth: isTargeted ? 2 : 0)
                .padding(10)
        )
        .dropDestination(for: URL.self) { urls, _ in
            importFiles(urls)
            return true
        } isTargeted: { value in
            isTargeted = value
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageHeading(
                title: "Импорт и экспорт",
                subtitle: "JSON, M3U или OPML — перенос библиотеки между плеерами"
            )
            Spacer()
            CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть") {
                dismiss()
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: Space.m) {
            Text("РЕЖИМ")
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Picker("", selection: $mode) {
                ForEach(StationImportMode.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Spacer()
        }
    }

    private var formatPicker: some View {
        HStack(spacing: Space.m) {
            Text("ФОРМАТ")
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Picker("", selection: $format) {
                ForEach(StationTransferFormat.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: Space.m) {
            SecondaryButton(title: "Импортировать", systemImage: "square.and.arrow.down") {
                chooseImport()
            }
            SecondaryButton(title: "Экспортировать", systemImage: "square.and.arrow.up") {
                chooseExport()
            }
            Spacer()
        }
    }

    private var dropZone: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textTertiary)
            Text("Перетащите файл сюда")
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
            Text("Режим «Добавить» не создаёт дубликаты, «Заменить» сохраняет избранное.")
                .font(Typeface.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(
                    isTargeted ? palette.accent : palette.separator,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        )
    }

    // MARK: - Files

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = supportedTypes
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "RadioMac.\(format.fileExtension)"
        panel.allowedContentTypes = [contentType(for: format)]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try StationTransfer.export(stations: library.stations, format: format)
            try data.write(to: url, options: .atomic)
            toasts.show("Экспортировано станций: \(library.stations.count)", kind: .success)
        } catch {
            toasts.show(error.localizedDescription, kind: .error)
        }
    }

    private func importFiles(_ urls: [URL]) {
        var total = StationImportResult()
        var errors: [String] = []
        for url in urls {
            guard let format = StationTransfer.detectFormat(for: url) else {
                errors.append("\(url.lastPathComponent): неизвестный формат")
                continue
            }
            do {
                let data = try Data(contentsOf: url)
                let stations = try StationTransfer.parse(data: data, format: format)
                let imported = library.importStations(stations, mode: mode)
                total.added += imported.added
                total.skipped += imported.skipped
                total.favoritesUpdated += imported.favoritesUpdated
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        result = total
        if errors.isEmpty {
            toasts.show(
                "Импорт: +\(total.added), пропущено \(total.skipped)",
                kind: .success
            )
        } else {
            toasts.show(errors.joined(separator: "\n"), kind: .error)
        }
    }

    private var supportedTypes: [UTType] {
        [
            .json,
            .xml,
            UTType(filenameExtension: "m3u"),
            UTType(filenameExtension: "m3u8"),
            UTType(filenameExtension: "opml"),
        ].compactMap { $0 }
    }

    private func contentType(for format: StationTransferFormat) -> UTType {
        switch format {
        case .json: return .json
        case .m3u: return UTType(filenameExtension: "m3u") ?? .plainText
        case .opml: return UTType(filenameExtension: "opml") ?? .xml
        }
    }
}
