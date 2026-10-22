import SwiftUI

/// Left column: big editorial genre navigation and the current artwork.
struct GenreNav: View {
    @ObservedObject var model: MainViewModel
    @ObservedObject var library: StationLibrary
    @ObservedObject var player: RadioPlayerService

    @Environment(\.palette) private var palette

    private enum ItemID: Hashable {
        case all
        case favorites
        case genre(String)
        case group(String)

        init(_ filter: StationFilter) {
            switch filter {
            case .all: self = .all
            case .favorites: self = .favorites
            case .genre(let name): self = .genre(name)
            case .group(let name): self = .group(name)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    NavItem(
                        label: "Все",
                        isSelected: model.filter == .all,
                        isPlaying: player.isPlaying
                    ) {
                        model.setFilter(.all)
                    }
                    .id(ItemID.all)

                    NavItem(
                        label: "Избранное",
                        isSelected: model.filter == .favorites,
                        isPlaying: player.isPlaying
                    ) {
                        model.setFilter(.favorites)
                    }
                    .id(ItemID.favorites)

                    if !library.groups.isEmpty {
                        sectionLabel("Группы")
                        ForEach(library.groups, id: \.self) { group in
                            NavItem(
                                label: group,
                                isSelected: model.filter == .group(group),
                                isPlaying: player.isPlaying
                            ) {
                                model.setFilter(.group(group))
                            }
                            .id(ItemID.group(group))
                        }
                    }

                    sectionLabel("Жанры")

                    ForEach(library.genres, id: \.self) { genre in
                        NavItem(
                            label: genre,
                            isSelected: model.filter == .genre(genre),
                            isPlaying: player.isPlaying
                        ) {
                            model.setFilter(.genre(genre))
                        }
                        .id(ItemID.genre(genre))
                    }
                }
                .padding(.trailing, Space.s)
            }
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: model.filter) { _, filter in
                withAnimation(Motion.content) {
                    proxy.scrollTo(ItemID(filter), anchor: .center)
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typeface.overline)
            .tracking(1.1)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Square hero artwork of the current station / track.
struct HeroArtwork: View {
    let station: RadioStation?
    let artworkURL: String?
    var onTap: (() -> Void)?

    @Environment(\.palette) private var palette

    private var resolvedURL: String? {
        if let artworkURL, !artworkURL.isEmpty { return artworkURL }
        guard let station, station.hasLogo else { return nil }
        return station.logoURL
    }

    var body: some View {
        ZStack {
            palette.surfaceRaised

            if let resolvedURL {
                RemoteImage(urlString: resolvedURL) {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 190, height: 190)
        .clipped()
        .overlay(Rectangle().strokeBorder(palette.separator, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .help(station.map { "\($0.name) — пауза / играть" } ?? "Нет активной станции")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(station.map { "Обложка: \($0.name)" } ?? "Нет обложки")
        .accessibilityAddTraits(station == nil ? .isImage : [.isButton, .isImage])
    }

    private var placeholder: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 30, weight: .light))
            .foregroundStyle(palette.textTertiary)
    }
}
