import AppIntents
import SwiftUI
import WidgetKit

struct RadioMacEntry: TimelineEntry {
    let date: Date
    let state: SharedPlaybackState?
}

struct RadioMacProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadioMacEntry {
        RadioMacEntry(date: Date(), state: nil)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (RadioMacEntry) -> Void
    ) {
        completion(RadioMacEntry(date: Date(), state: SharedPlaybackState.load()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<RadioMacEntry>) -> Void
    ) {
        let entry = RadioMacEntry(date: Date(), state: SharedPlaybackState.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
}

struct RadioMacWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "com.fso13.radioMac.widget",
            provider: RadioMacProvider()
        ) { entry in
            RadioMacWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("RadioMac")
        .description("Текущая станция и управление воспроизведением.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RadioMacWidgetView: View {
    let entry: RadioMacEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("RadioMac")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                Spacer()
                if let state = entry.state {
                    Link(destination: URL(string: state.isPlaying ? "radiomac://pause" : "radiomac://play/\(state.stationID)")!) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 2)

            if let state = entry.state, !state.stationName.isEmpty {
                Text(state.stationName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(state.track ?? (state.isPlaying ? "Играет" : "Пауза"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Запустите RadioMac")
                    .font(.system(size: 14, weight: .medium))
                Text("Станция появится здесь")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(2)
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
struct RadioMacControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fso13.radioMac.control") {
            ControlWidgetButton(
                action: OpenURLIntent(URL(string: "radiomac://toggle")!)
            ) {
                Label("RadioMac", systemImage: "playpause.fill")
            }
        }
        .displayName("RadioMac")
        .description("Играть или поставить на паузу.")
    }
}
#endif

@main
struct RadioMacWidgetBundle: WidgetBundle {
    var body: some Widget {
        RadioMacWidget()
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            RadioMacControl()
        }
#endif
    }
}
