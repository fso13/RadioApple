import SwiftUI

/// Directory search over Radio Browser with stream preview and duplicate-safe add.
struct RadioBrowserView: View {
    @ObservedObject var library: StationLibrary
    @ObservedObject var player: RadioPlayerService
    @ObservedObject var toasts: ToastCenter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @StateObject private var service = RadioBrowserService()

    @State private var name = ""
    @State private var genre = ""
    @State private var country = ""

    var body: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                searchBar
                Hairline()
                results
            }
            .padding(Space.xxl)
        }
        .frame(width: 760, height: 610)
        .onDisappear { service.cancel() }
        .onReceive(service.$errorText) { message in
            guard !message.isEmpty else { return }
            toasts.show(message, kind: .error)
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .bottom, spacing: Space.l) {
                EditorialField(title: "Название", text: $name, placeholder: "Jazz FM")
                EditorialField(title: "Жанр", text: $genre, placeholder: "jazz")
                EditorialField(title: "Страна", text: $country, placeholder: "Germany")
            }
            searchControls
        }
    }

    private var searchControls: some View {
        HStack(spacing: Space.m) {
            PrimaryButton(
                title: "Найти",
                systemImage: "magnifyingglass",
                isEnabled: !service.isLoading
            ) {
                service.search(name: name, genre: genre, country: country)
            }
            if service.isLoading {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Text("Каталог Radio Browser")
                .font(Typeface.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageHeading(
                title: "Radio Browser",
                subtitle: "Тысячи станций по названию, жанру и стране"
            )
            Spacer()
            CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть") {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if service.results.isEmpty {
            VStack(spacing: Space.m) {
                Spacer()
                BrandMark(fontSize: 24)
                Text(service.isLoading ? "Ищем станции…" : "Найдите станцию в каталоге")
                    .font(Typeface.body)
                    .foregroundStyle(palette.textSecondary)
                Text("Введите название, жанр или страну и нажмите «Найти».")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(service.results) { item in
                        row(item)
                        Hairline()
                    }
                    loadMoreRow
                }
            }
        }
    }

    private var loadMoreRow: some View {
        TextButton(
            title: service.hasMore ? "Показать ещё" : "Больше нет",
            systemImage: "arrow.down",
            iconPosition: .trailing
        ) {
            service.loadMore()
        }
        .disabled(!service.hasMore)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
    }

    private func row(_ item: RadioBrowserStation) -> some View {
        let station = item.asRadioStation()
        let duplicate = library.isDuplicate(
            url: station.url,
            externalID: item.stationuuid
        )
        return HStack(spacing: Space.m) {
            StationLogo(station: station, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Typeface.body)
                    .fontWeight(.medium)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(item.details)
                    .font(Typeface.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.genre)
                .font(Typeface.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            rowActions(item: item, station: station, duplicate: duplicate)
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
    }

    private func rowActions(
        item: RadioBrowserStation,
        station: RadioStation,
        duplicate: Bool
    ) -> some View {
        HStack(spacing: Space.s) {
            CircleIconButton(systemName: "play.fill", size: 11, help: "Превью") {
                player.play(station, persist: false)
            }
            CircleIconButton(
                systemName: duplicate ? "checkmark" : "plus",
                size: 11,
                help: duplicate ? "Уже в библиотеке" : "Добавить"
            ) {
                add(item, station: station, duplicate: duplicate)
            }
            .disabled(duplicate)
        }
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
        toasts.show("«\(item.name)» добавлена", kind: .success)
    }
}