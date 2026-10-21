import AppKit
import SwiftUI

/// Sheet with the local diagnostics journal. Nothing is uploaded; the user can
/// copy or clear the entries.
struct DiagnosticsView: View {
    @ObservedObject var diagnostics: DiagnosticsService
    let onClose: () -> Void

    @Environment(\.palette) private var palette
    @State private var confirmClear = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                PageHeading(title: "Журнал", subtitle: "Локально · без отправки")
                Spacer()
                CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть", action: onClose)
            }

            if diagnostics.lines.isEmpty {
                EmptyStateView(
                    systemImage: "doc.text",
                    title: "Журнал пуст",
                    subtitle: "Включите локальный журнал в настройках — сюда попадут события плеера, станции и ошибки."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(diagnostics.lines.joined(separator: "\n"))
                        .font(Typeface.monoSmall)
                        .foregroundStyle(palette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.m)
                }
                .background(palette.surfaceRaised)
                .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
                .defaultScrollAnchor(.bottom)
            }

            HStack(spacing: Space.l) {
                TextButton(
                    title: copied ? "Скопировано" : "Скопировать",
                    systemImage: "doc.on.doc"
                ) {
                    copy()
                }
                .disabled(diagnostics.lines.isEmpty)

                TextButton(title: "Очистить", systemImage: "trash") {
                    confirmClear = true
                }
                .disabled(diagnostics.lines.isEmpty)

                Spacer()
                PrimaryButton(title: "Готово", action: onClose)
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 640, height: 540)
        .background(palette.surface)
        .alert("Очистить журнал?", isPresented: $confirmClear) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) { diagnostics.clear() }
        } message: {
            Text("Записи журнала будут удалены с этого Mac.")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(diagnostics.copyText(), forType: .string) else {
            return
        }
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
