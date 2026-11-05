import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Manual cover editor: pick an image file, paste a URL or take a candidate
/// from the online catalogues. Nothing is written to the audio file.
struct MusicArtworkEditorView: View {
    let editor: MusicArtworkEditor

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var urlString: String
    @State private var candidates: [TrackEnrichment] = []
    @State private var isSearching = false
    @State private var message: String?

    init(editor: MusicArtworkEditor) {
        self.editor = editor
        _urlString = State(initialValue: editor.currentURL ?? "")
    }

    private var previewURL: String? {
        LocalTrack.trimmed(urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header

            HStack(alignment: .top, spacing: Space.l) {
                preview
                controls
            }

            if !candidates.isEmpty {
                candidateList
            }

            Spacer(minLength: 0)

            HStack {
                TextButton(title: "Отмена") { dismiss() }
                Spacer()
                PrimaryButton(title: "Сохранить") {
                    editor.save(previewURL)
                    dismiss()
                }
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 600, height: 560)
        .background(palette.surface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            PageHeading(
                title: LocalizedStringKey(editor.title),
                subtitle: editor.subtitle.map { LocalizedStringKey($0) }
            )
            Spacer()
            CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть") {
                dismiss()
            }
        }
    }

    private var preview: some View {
        ZStack {
            palette.surfaceRaised
            if let previewURL {
                RemoteImage(urlString: previewURL) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 170, height: 170)
        .clipped()
        .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                SecondaryButton(
                    title: isSearching ? "Ищу…" : "Найти в сети",
                    systemImage: "magnifyingglass"
                ) {
                    findOnline()
                }
                .disabled(isSearching)

                SecondaryButton(title: "Выбрать файл…", systemImage: "folder") {
                    chooseFile()
                }

                if previewURL != nil {
                    TextButton(title: "Убрать", systemImage: "xmark", tint: palette.red) {
                        urlString = ""
                        message = nil
                    }
                }
            }

            if let note = editor.note {
                Text(note)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Text(message)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            EditorialField(
                title: "Ссылка на изображение",
                text: $urlString,
                placeholder: "https://… или file://…",
                isMonospaced: true,
                footnote: "Можно вставить ссылку вручную. Изображение сохранится в кэше приложения, аудиофайл не изменяется."
            )

            Spacer(minLength: 0)
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("ВАРИАНТЫ ИЗ СЕТИ")
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            ScrollView(.horizontal) {
                HStack(spacing: Space.s) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                        if let artwork = candidate.artworkURL {
                            candidateButton(candidate, artwork: artwork)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 86)
        }
    }

    private func candidateButton(_ candidate: TrackEnrichment, artwork: String) -> some View {
        let selected = artwork == previewURL
        return Button {
            urlString = artwork
            message = "Выбрано: \(candidate.source). Сохраните, чтобы применить."
        } label: {
            RemoteImage(urlString: artwork) {
                palette.surfaceRaised
            }
            .frame(width: 72, height: 72)
            .clipped()
            .overlay(
                Rectangle()
                    .strokeBorder(
                        selected ? palette.accent : palette.separator,
                        lineWidth: selected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(candidate.title ?? "Обложка") · \(candidate.source)")
        .accessibilityLabel("Обложка из \(candidate.source)")
    }

    // MARK: - Actions

    private func findOnline() {
        Task { @MainActor in
            isSearching = true
            message = nil
            let found = await editor.search().filter { $0.artworkURL != nil }
            candidates = found
            isSearching = false
            guard let first = found.first?.artworkURL else {
                message = "В сети ничего не нашлось — выберите файл или укажите ссылку."
                return
            }
            urlString = first
            message = "Найдено вариантов: \(found.count). Выберите обложку ниже."
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Выбрать"
        panel.message = "Выберите изображение обложки"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            message = "Не удалось прочитать выбранный файл."
            return
        }
        guard let stored = MusicArtworkStore.save(data, for: "cover-\(UUID().uuidString)") else {
            message = "Не удалось сохранить обложку в кэш приложения."
            return
        }
        urlString = stored
        message = "Файл скопирован в кэш обложек. Сохраните, чтобы применить."
    }
}
