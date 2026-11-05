import SwiftUI
import UniformTypeIdentifiers

/// Album/artist cover editor: online candidates, a custom URL or an image from
/// the Files app. The image is cached by the app; audio files stay untouched.
struct MusicArtworkEditorScreen: View {
    let editor: MusicArtworkEditor

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var urlString: String
    @State private var candidates: [TrackEnrichment] = []
    @State private var isSearching = false
    @State private var message: String?
    @State private var choosingImage = false

    init(editor: MusicArtworkEditor) {
        self.editor = editor
        _urlString = State(initialValue: editor.currentURL ?? "")
    }

    private var previewURL: String? {
        LocalTrack.trimmed(urlString)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    previewRow
                    EditorialField(
                        title: "Ссылка на изображение",
                        text: $urlString,
                        placeholder: "https://… или file://…",
                        isMonospaced: true,
                        footnote: "Картинка сохранится в кэше приложения. Аудиофайл не изменяется."
                    )

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !candidates.isEmpty {
                        candidatesSection
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
            }

            footer
        }
        .background(palette.window)
        .fileImporter(
            isPresented: $choosingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            importImage(result)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.title)
                    .font(.title3.bold())
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let subtitle = editor.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            CircleIconButton(systemName: "xmark", size: 12, help: "Закрыть") {
                dismiss()
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.m)
    }

    private var previewRow: some View {
        HStack(alignment: .top, spacing: Space.m) {
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
            .frame(width: 150, height: 150)
            .clipped()
            .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))

            VStack(alignment: .leading, spacing: Space.s) {
                SecondaryButton(
                    title: isSearching ? "Ищу…" : "Найти в сети",
                    systemImage: "magnifyingglass"
                ) {
                    findOnline()
                }
                .disabled(isSearching)

                SecondaryButton(title: "Выбрать файл", systemImage: "photo") {
                    choosingImage = true
                }

                if previewURL != nil {
                    TextButton(title: "Убрать", systemImage: "xmark", tint: palette.red) {
                        urlString = ""
                        message = nil
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "Варианты из сети")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                        if let artwork = candidate.artworkURL {
                            candidateButton(candidate, artwork: artwork)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
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
            .frame(width: 76, height: 76)
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
        .accessibilityLabel("Обложка из \(candidate.source)")
    }

    private var footer: some View {
        HStack {
            TextButton(title: "Отмена") { dismiss() }
            Spacer()
            PrimaryButton(title: "Сохранить") {
                editor.save(previewURL)
                dismiss()
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(palette.surface)
        .overlay(alignment: .top) { Hairline() }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - Actions

    private func findOnline() {
        Task {
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

    private func importImage(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
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
