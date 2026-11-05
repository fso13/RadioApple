import SwiftUI
import UniformTypeIdentifiers

/// Track metadata editor with manual fields and online catalogue search.
/// Nothing is written to the audio file: edits live in the library.
struct MusicTrackEditorScreen: View {
    let track: LocalTrack

    @EnvironmentObject private var music: MusicLibrary
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var genre: String
    @State private var year: String
    @State private var trackNumber: String
    @State private var artworkURL: String

    @State private var candidates: [TrackEnrichment] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var message: String?
    @State private var choosingImage = false

    init(track: LocalTrack) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist ?? "")
        _album = State(initialValue: track.album ?? "")
        _genre = State(initialValue: track.genre ?? "")
        _year = State(initialValue: track.year.map(String.init) ?? "")
        _trackNumber = State(initialValue: track.trackNumber.map(String.init) ?? "")
        _artworkURL = State(initialValue: track.artworkURL ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    EditorialField(title: "Название", text: $title)
                    EditorialField(title: "Исполнитель", text: $artist)
                    EditorialField(title: "Альбом", text: $album)

                    HStack(alignment: .top, spacing: Space.m) {
                        EditorialField(title: "Жанр", text: $genre)
                        EditorialField(title: "Год", text: $year, isMonospaced: true)
                        EditorialField(title: "Номер", text: $trackNumber, isMonospaced: true)
                    }

                    coverSection
                    onlineSection

                    Text(track.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            importCover(result)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Метаданные трека")
                    .font(.title3.bold())
                    .foregroundStyle(palette.textPrimary)
                Text("Правки хранятся в библиотеке, файл не изменяется")
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
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

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title: "Обложка")

            HStack(spacing: Space.m) {
                ZStack {
                    palette.surfaceRaised

                    if let preview = LocalTrack.trimmed(artworkURL) {
                        RemoteImage(urlString: preview) {
                            placeholder
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(width: 64, height: 64)
                .clipped()
                .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: Space.s) {
                    SecondaryButton(title: "Выбрать файл", systemImage: "photo") {
                        choosingImage = true
                    }
                    if LocalTrack.trimmed(artworkURL) != nil {
                        TextButton(title: "Убрать", systemImage: "xmark", tint: palette.red) {
                            artworkURL = ""
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            EditorialField(
                title: "Ссылка на изображение",
                text: $artworkURL,
                placeholder: "https://… или file://…",
                isMonospaced: true
            )
        }
    }

    private var onlineSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                SectionLabel(title: "Онлайн-поиск")
                Spacer()
                SecondaryButton(
                    title: isSearching ? "Ищу…" : "Найти в сети",
                    systemImage: "magnifyingglass"
                ) {
                    Task { await searchOnline() }
                }
                .disabled(isSearching)
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !candidates.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(candidates.prefix(6).enumerated()), id: \.offset) { _, candidate in
                        candidateRow(candidate)
                        Hairline()
                    }
                }
                .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
            } else if didSearch, !isSearching, message == nil {
                Text("Совпадений не нашлось.")
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func candidateRow(_ candidate: TrackEnrichment) -> some View {
        Button {
            apply(candidate)
        } label: {
            HStack(spacing: Space.m) {
                ZStack {
                    palette.surfaceRaised

                    RemoteImage(urlString: candidate.artworkURL) {
                        Image(systemName: "music.note")
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .frame(width: 40, height: 40)
                .clipped()
                .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title ?? "Без названия")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(candidate.summary)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.s)

                Text("\(Int((candidate.matchScore * 100).rounded()))%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            TextButton(title: "Отмена") { dismiss() }
            Spacer()
            PrimaryButton(title: "Сохранить") { save() }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(palette.surface)
        .overlay(alignment: .top) { Hairline() }
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - Actions

    private func searchOnline() async {
        isSearching = true
        message = nil
        let queryTitle = LocalTrack.trimmed(title) ?? track.displayTitle
        let results = await MetadataEnrichmentService.shared.candidates(
            title: queryTitle,
            artist: LocalTrack.trimmed(artist) ?? track.displayArtist,
            album: LocalTrack.trimmed(album) ?? track.displayAlbum
        )
        candidates = results
        didSearch = true
        isSearching = false
        if results.isEmpty {
            message = "Ничего не нашлось — уточните исполнителя и название."
        }
    }

    private func apply(_ candidate: TrackEnrichment) {
        if let value = LocalTrack.trimmed(candidate.title) { title = value }
        if let value = LocalTrack.trimmed(candidate.artist) { artist = value }
        if let value = LocalTrack.trimmed(candidate.album) { album = value }
        if let value = LocalTrack.trimmed(candidate.genre) { genre = value }
        if let value = candidate.year { year = String(value) }
        if let value = LocalTrack.trimmed(candidate.artworkURL) { artworkURL = value }
        message = "Подставлено из \(candidate.source). Сохраните, чтобы применить."
    }

    private func importCover(_ result: Result<[URL], Error>) {
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
        artworkURL = stored
        message = "Файл скопирован в кэш обложек. Сохраните, чтобы применить."
    }

    private func save() {
        var updated = track
        updated.title = title
        updated.artist = artist
        updated.album = album
        updated.genre = genre
        updated.year = Int(year.trimmingCharacters(in: .whitespaces))
        updated.trackNumber = Int(trackNumber.trimmingCharacters(in: .whitespaces))
        updated.artworkURL = artworkURL
        if LocalTrack.trimmed(artworkURL) != nil {
            updated.enrichmentSource = candidates.first {
                $0.artworkURL == updated.artworkURL
            }?.source ?? "Онлайн-поиск"
            updated.enrichedAt = Date()
        }
        music.update(updated)
        dismiss()
    }
}
