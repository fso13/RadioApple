import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: TrackHistoryService
    let onClose: () -> Void

    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var confirmClear = false

    private var items: [TrackHistoryEntry] { history.filtered(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                PageHeading(
                    title: "История треков",
                    subtitle: "Последние 100 треков · только на этом Mac"
                )
                Spacer()
                CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть", action: onClose)
            }

            HStack(spacing: Space.m) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
                TextField("Поиск по станции или треку", text: $query)
                    .textFieldStyle(.plain)
                    .font(Typeface.body)
                    .accessibilityLabel("Поиск по истории")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Hairline() }

            if items.isEmpty {
                VStack(spacing: Space.m) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                    Text(history.entries.isEmpty ? "История пока пуста" : "Ничего не найдено")
                        .font(Typeface.body)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { entry in
                            row(entry)
                            Hairline()
                        }
                    }
                }
            }

            HStack(spacing: Space.m) {
                TextButton(title: "Скопировать всё", systemImage: "doc.on.doc") {
                    copy(items)
                }
                .disabled(items.isEmpty)
                TextButton(title: "Очистить", systemImage: "trash") {
                    confirmClear = true
                }
                .disabled(history.entries.isEmpty)
                Spacer()
                Text("\(items.count) из \(history.entries.count)")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.xxl)
        .frame(width: 700, height: 620)
        .background(palette.surface)
        .alert("Очистить историю?", isPresented: $confirmClear) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) { history.clear() }
        } message: {
            Text("История хранится только локально и будет удалена без возможности восстановления.")
        }
    }

    private func row(_ entry: TrackHistoryEntry) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.line)
                    .font(Typeface.body)
                    .fontWeight(.medium)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(entry.stationName)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Self.dateFormatter.string(from: entry.playedAt))
                .font(Typeface.monoSmall)
                .foregroundStyle(palette.textTertiary)
            CircleIconButton(systemName: "doc.on.doc", size: 10, help: "Скопировать") {
                copy([entry])
            }
        }
        .padding(.vertical, Space.s)
    }

    private func copy(_ items: [TrackHistoryEntry]) {
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(history.copyText(items), forType: .string)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter
    }()
}
