import SwiftUI

struct StationDraft {
    var name: String
    var url: String
    var genre: String
    var comment: String
    var group: String
    var logoURL: String
    var volumeOffsetDB: Double
    var eqPresetID: String?
    var autoplay: Bool
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
    @State private var group: String
    @State private var logoURL: String
    @State private var volumeOffsetDB: Double
    @State private var eqPresetID: String?
    @State private var autoplay: Bool

    init(existing: RadioStation?, genres: [String], onSave: @escaping (StationDraft) -> Void) {
        self.existing = existing
        self.genres = genres
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _url = State(initialValue: existing?.url ?? "")
        _genre = State(initialValue: existing?.genre ?? GenreCatalog.other)
        _comment = State(initialValue: existing?.comment ?? "")
        _group = State(initialValue: existing?.group ?? "")
        _logoURL = State(initialValue: existing?.logoURL ?? "")
        _volumeOffsetDB = State(initialValue: existing?.volumeOffsetDB ?? 0)
        _eqPresetID = State(initialValue: existing?.eqPresetID)
        _autoplay = State(initialValue: existing?.autoplay ?? false)
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
                        title: "Группа",
                        text: $group,
                        placeholder: "Например, Утро",
                        footnote: "Необязательно. Группы появятся в навигации слева."
                    )

                    EditorialField(
                        title: "Логотип",
                        text: $logoURL,
                        placeholder: "URL картинки",
                        isMonospaced: true,
                        footnote: "Если пусто — логотип найдётся по ссылке потока."
                    )

                    stationTuning
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
                            group: group,
                            logoURL: logoURL,
                            volumeOffsetDB: volumeOffsetDB,
                            eqPresetID: eqPresetID,
                            autoplay: autoplay
                        )
                    )
                    dismiss()
                }
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 540, height: 720)
        .background(palette.surface)
    }

    private var stationTuning: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("НАСТРОЙКИ СТАНЦИИ")
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            HStack(spacing: Space.m) {
                Text("Смещение громкости")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                Slider(value: $volumeOffsetDB, in: -12...12, step: 1)
                Text(String(format: "%+.0f dB", volumeOffsetDB))
                    .font(Typeface.mono)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 54, alignment: .trailing)
            }

            HStack(spacing: Space.m) {
                Text("EQ-пресет")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                Picker("", selection: $eqPresetID) {
                    Text("Как в приложении").tag(String?.none)
                    ForEach(EqualizerCatalog.presets.filter { $0.id != EqualizerCatalog.customID }) { preset in
                        Text(preset.label).tag(Optional(preset.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Spacer()
            }

            Toggle("Запускать при старте RadioMac", isOn: $autoplay)
                .toggleStyle(.switch)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.xs)
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
