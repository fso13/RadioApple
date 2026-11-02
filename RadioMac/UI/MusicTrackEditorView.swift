import SwiftUI

/// Edit a track's metadata by hand or pull it from an online catalogue.
struct MusicTrackEditorView: View {
    let track: LocalTrack
    let library: MusicLibrary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

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

    init(track: LocalTrack, library: MusicLibrary) {
        self.track = track
        self.library = library
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist ?? "")
        _album = State(initialValue: track.album ?? "")
        _genre = State(initialValue: track.genre ?? "")
        _year = State(initialValue: track.year.map(String.init) ?? "")
        _trackNumber = State(initialValue: track.trackNumber.map(String.init) ?? "")
        _artworkURL = State(initialValue: track.artworkURL ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    EditorialField(title: "Название", text: $title)
                    EditorialField(title: "Исполнитель", text: $artist)
                    EditorialField(title: "Альбом", text: $album)

                    HStack(alignment: .top, spacing: Space.l) {
                        EditorialField(title: "Жанр", text: $genre)
                        EditorialField(title: "Год", text: $year, isMonospaced: true)
                        EditorialField(title: "Номер", text: $trackNumber, isMonospaced: true)
                    }

                    EditorialField(
                        title: "Обложка",
                        text: $artworkURL,
                        placeholder: "URL картинки",
                        isMonospaced: true,
                        footnote: "Ссылка на изображение или file:// из кэша приложения."
                    )

                    onlineSection

                    Text(track.path)
                        .font(Typeface.monoSmall)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(track.path)
                }
                .padding(.vertical, Space.xs)
            }

            HStack {
                TextButton(title: "Отмена") { dismiss() }
                Spacer()
                PrimaryButton(title: "Сохранить") { save() }
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 560, height: 720)
        .background(palette.surface)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                PageHeading(
                    title: "Метаданные трека",
                    subtitle: "Правки хранятся в библиотеке, файл не изменяется"
                )
                Text(track.fileName)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть") {
                dismiss()
            }
        }
    }

    private var onlineSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Text("ОНЛАЙН-ПОИСК")
                    .font(Typeface.overline)
                    .tracking(1.2)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                SecondaryButton(title: isSearching ? "Ищу…" : "Найти в сети", systemImage: "magnifyingglass") {
                    Task { await searchOnline() }
                }
                .disabled(isSearching)
                .padding(.trailing, Space.scrollLane)
            }

            if let message {
                Text(message)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !candidates.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(candidates.prefix(6).enumerated()), id: \.offset) { _, candidate in
                        candidateRow(candidate)
                    }
                }
                .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
            } else if didSearch, !isSearching, candidates.isEmpty, message == nil {
                Text("Совпадений не нашлось.")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, Space.s)
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
                .frame(width: 34, height: 34)
                .clipped()
                .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title ?? "Без названия")
                        .font(Typeface.captionMedium)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(candidate.summary)
                        .font(Typeface.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(Int((candidate.matchScore * 100).rounded()))%")
                    .font(Typeface.monoSmall)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
        .help("Подставить эти данные")
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
        library.update(updated)
        dismiss()
    }
}
