import SwiftUI

struct StationDraft {
    var name: String
    var url: String
    var genre: String
    var comment: String
    var logoURL: String
}

/// Add/edit station sheet in the same editorial language as the main page.
struct StationEditorView: View {
    let existing: RadioStation?
    let genres: [String]
    let onSave: (StationDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var name: String
    @State private var url: String
    @State private var genre: String
    @State private var comment: String
    @State private var logoURL: String

    init(existing: RadioStation?, genres: [String], onSave: @escaping (StationDraft) -> Void) {
        self.existing = existing
        self.genres = genres
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _url = State(initialValue: existing?.url ?? "")
        _genre = State(initialValue: existing?.genre ?? GenreCatalog.other)
        _comment = State(initialValue: existing?.comment ?? "")
        _logoURL = State(initialValue: existing?.logoURL ?? "")
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsed.scheme?.isEmpty == false,
              parsed.host?.isEmpty == false
        else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                PageHeading(
                    title: existing == nil ? "Новая станция" : "Изменить станцию",
                    subtitle: "Прямая ссылка на аудиопоток"
                )
                Spacer()
                CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть") {
                    dismiss()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    EditorialField(
                        title: "Название",
                        text: $name,
                        placeholder: "Например, Radio Paradise"
                    )

                    EditorialField(
                        title: "Ссылка на поток",
                        text: $url,
                        placeholder: "https://example.com/stream.mp3",
                        isMonospaced: true,
                        footnote: "Страница радиостанции не подойдёт — нужен адрес аудио."
                    )

                    genreChoices

                    EditorialField(
                        title: "Комментарий",
                        text: $comment,
                        placeholder: "Необязательно"
                    )

                    EditorialField(
                        title: "Логотип",
                        text: $logoURL,
                        placeholder: "URL картинки",
                        isMonospaced: true,
                        footnote: "Если пусто — логотип найдётся по ссылке потока."
                    )
                }
                .padding(.vertical, Space.xs)
            }

            HStack {
                TextButton(title: "Отмена") { dismiss() }
                Spacer()
                PrimaryButton(
                    title: existing == nil ? "Добавить" : "Сохранить",
                    isEnabled: isValid
                ) {
                    guard isValid else { return }
                    onSave(
                        StationDraft(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                            genre: genre,
                            comment: comment,
                            logoURL: logoURL
                        )
                    )
                    dismiss()
                }
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 520, height: 620)
        .background(palette.surface)
    }

    private var genreChoices: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("ЖАНР")
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            FlowLayout(spacing: Space.l, lineSpacing: Space.s) {
                ForEach(genres, id: \.self) { value in
                    let isSelected = GenreCatalog.normalize(genre) == value
                    Button {
                        genre = value
                    } label: {
                        VStack(spacing: 3) {
                            Text(value)
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
            }
        }
    }
}

/// Label above, hairline input below — the form language of the reference.
struct EditorialField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var isMonospaced: Bool = false
    var footnote: String?

    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundColor(palette.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(isMonospaced ? Typeface.mono : Typeface.body)
            .foregroundStyle(palette.textPrimary)
            .focused($isFocused)
            .padding(.vertical, 5)

            Rectangle()
                .fill(isFocused ? palette.textPrimary : palette.separator)
                .frame(height: 1)
                .animation(Motion.hover, value: isFocused)

            if let footnote {
                Text(footnote)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
