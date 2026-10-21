import AppKit
import SwiftUI

struct LastFmSetupView: View {
    @ObservedObject var lastFm: LastFmService
    let onClose: () -> Void

    @Environment(\.palette) private var palette
    @State private var apiKey = ""
    @State private var apiSecret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                PageHeading(title: "Last.fm", subtitle: "Opt-in скробблинг")
                Spacer()
                CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть", action: onClose)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    content
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Space.m) {
                Text("Ключи и сессия хранятся в Keychain. Данные уходят только на Last.fm.")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                PrimaryButton(title: "Готово", action: onClose)
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 600, height: 560)
        .background(palette.surface)
    }

    @ViewBuilder
    private var content: some View {
        if lastFm.isConnected {
            InfoRow(label: "Аккаунт", value: lastFm.username ?? "—")
            Text("Скробблинг включён. Now-playing отправляется при смене трека, скроббл — после 4 минут прослушивания.")
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            DestructiveButton(title: "Отключить Last.fm") {
                lastFm.disconnect()
            }
        } else if lastFm.pendingToken != nil {
            Text("Last.fm открыт в браузере. Авторизуйте RadioMac и вернитесь сюда, затем нажмите «Готово».")
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.m) {
                SecondaryButton(title: "Открыть Last.fm снова") {
                    if let url = lastFm.pendingAuthURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                PrimaryButton(
                    title: lastFm.isAuthorizing ? "Проверяем…" : "Готово",
                    isEnabled: !lastFm.isAuthorizing
                ) {
                    lastFm.completeAuthorization()
                }
            }
        } else if lastFm.credentials == nil {
            Text("Создайте API-ключи приложения Last.fm и вставьте их сюда. Секрет хранится только в Keychain.")
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(
                "Создать ключи на Last.fm",
                destination: URL(string: "https://www.last.fm/api/account/create")!
            )
            .font(Typeface.body)
            .foregroundStyle(palette.textPrimary)

            EditorialField(
                title: "API key",
                text: $apiKey,
                placeholder: "ключ приложения",
                isMonospaced: true
            )
            secretField

            PrimaryButton(
                title: lastFm.isAuthorizing ? "Открываем…" : "Сохранить и открыть Last.fm",
                isEnabled: !lastFm.isAuthorizing
            ) {
                if lastFm.saveCredentials(apiKey: apiKey, apiSecret: apiSecret) {
                    lastFm.startAuthorization()
                }
            }
        } else {
            Text("Ключи сохранены. Осталось авторизовать аккаунт Last.fm.")
                .font(Typeface.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.m) {
                PrimaryButton(
                    title: lastFm.isAuthorizing ? "Открываем…" : "Открыть Last.fm",
                    isEnabled: !lastFm.isAuthorizing
                ) {
                    lastFm.startAuthorization()
                }
                TextButton(title: "Изменить ключи", systemImage: "key") {
                    lastFm.forgetCredentials()
                    apiKey = ""
                    apiSecret = ""
                }
            }
        }
    }

    private var secretField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("API SECRET")
                .font(Typeface.overline)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            SecureField(
                "",
                text: $apiSecret,
                prompt: Text("секрет приложения").foregroundColor(palette.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(Typeface.mono)
            .foregroundStyle(palette.textPrimary)
            .padding(.vertical, 5)

            Rectangle()
                .fill(palette.separator)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let error = lastFm.lastError {
            Text(error)
                .font(Typeface.caption)
                .foregroundStyle(palette.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let message = lastFm.statusMessage {
            Text(message)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
