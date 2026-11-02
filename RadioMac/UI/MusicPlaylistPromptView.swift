import SwiftUI

/// Small sheet for creating or renaming a playlist.
struct MusicPlaylistPromptView: View {
    let prompt: MusicPlaylistPrompt
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool
    @State private var name: String

    init(
        prompt: MusicPlaylistPrompt,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _name = State(initialValue: prompt.initialName)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PageHeading(
                title: prompt.mode == .create ? "Новый плейлист" : "Переименовать плейлист",
                subtitle: "Плейлист хранит ссылки на треки — файлы не копируются"
            )

            EditorialField(
                title: "Название",
                text: $name,
                placeholder: "Например, Вечерний джаз"
            )
            .focused($focused)
            .onSubmit(submit)

            HStack {
                TextButton(title: "Отмена", action: onCancel)
                Spacer()
                PrimaryButton(
                    title: prompt.mode == .create ? "Создать" : "Сохранить",
                    isEnabled: !trimmed.isEmpty
                ) {
                    submit()
                }
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 440)
        .background(palette.surface)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}
