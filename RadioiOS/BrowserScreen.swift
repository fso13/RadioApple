import SwiftUI

/// Radio Browser directory: search by name, genre and country, preview a
/// stream, then add it to the library once.
struct BrowserScreen: View {
    @Binding var showPlayer: Bool

    @EnvironmentObject private var library: StationLibrary
    @EnvironmentObject private var player: RadioPlayerService
    @Environment(\.palette) private var palette

    @StateObject private var service = RadioBrowserService()

    @State private var name = ""
    @State private var genre = ""
    @State private var country = ""
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                overline: "Каталог",
                title: "Radio Browser",
                subtitle: "название, жанр, страна"
            ) {
                if service.isLoading {
                    ProgressView()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    searchForm

                    if let notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(palette.green)
                            .transition(.opacity)
                    }

                    if !service.errorText.isEmpty {
                        Text(service.errorText)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }

                    Hairline()

                    results
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.m)
            }
            .refreshable {
                service.search(name: name, genre: genre, country: country)
            }
        }
        .background(palette.window)
        .miniPlayer { showPlayer = true }
        .onDisappear { service.cancel() }
    }

    // MARK: - Form

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            EditorialField(title: "Название", text: $name, placeholder: "Jazz FM") {
                runSearch()
            }
            EditorialField(title: "Жанр", text: $genre, placeholder: "jazz") {
                runSearch()
            }
            EditorialField(title: "Страна", text: $country, placeholder: "Germany") {
                runSearch()
            }

            PrimaryButton(
                title: "Найти",
                systemImage: "magnifyingglass",
                isEnabled: !service.isLoading,
                fullWidth: true
            ) {
                runSearch()
            }

            if !service.results.isEmpty {
                Text("\(service.results.count) результатов")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, Space.s)
    }

    private func runSearch() {
        notice = nil
        service.search(name: name, genre: genre, country: country)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if service.results.isEmpty {
            VStack(spacing: Space.m) {
                BrandMark(fontSize: 22, showsGlyph: true)
                    .padding(.top, Space.xxl)

                Text(service.isLoading ? "Ищем станции…" : "Найдите станцию в каталоге")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textSecondary)

                Text("Введите название, жанр или страну и нажмите «Найти».\nПревью играет поток, не добавляя его в библиотеку.")
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl)
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(service.results) { item in
                    row(item)
                    Hairline()
                }
            }
        }
    }

    private func row(_ item: RadioBrowserStation) -> some View {
        let station = item.asRadioStation()
        let duplicate = library.isDuplicate(
            url: station.url,
            externalID: item.stationuuid
        )

        return HStack(spacing: Space.m) {
            StationLogo(station: station, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(item.details.isEmpty ? item.genre : item.details)
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s)

            CircleIconButton(systemName: "play.fill", size: 12, help: "Превью") {
                player.play(station, persist: false)
            }

            Button {
                add(item, station: station, duplicate: duplicate)
            } label: {
                Image(systemName: duplicate ? "checkmark" : "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(duplicate ? palette.textTertiary : palette.textPrimary)
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(duplicate)
            .accessibilityLabel(duplicate ? "Уже в библиотеке" : "Добавить в библиотеку")
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
    }

    private func add(
        _ item: RadioBrowserStation,
        station: RadioStation,
        duplicate: Bool
    ) {
        guard !duplicate else { return }
        _ = library.add(
            name: item.name,
            url: station.url,
            genre: item.genre,
            comment: station.comment,
            logoURL: item.favicon,
            externalID: item.stationuuid
        )
        withAnimation(.easeOut(duration: 0.18)) {
            notice = "«\(item.name)» добавлена в библиотеку"
        }
    }
}
