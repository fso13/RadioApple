import SwiftUI

enum WindowRoute {
    case main
    case music
    case settings
}

enum WindowSheet: String, Identifiable {
    case equalizer
    case history

    var id: String { rawValue }
}

@MainActor
final class WindowRouter: ObservableObject {
    @Published var route: WindowRoute = .main
    @Published var sheet: WindowSheet?
}

/// Entry point of the SwiftUI hierarchy hosted inside the panel.
struct RootView: View {
    @ObservedObject var router: WindowRouter
    @ObservedObject var model: MainViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var theme: ThemeService
    @ObservedObject var library: StationLibrary
    @ObservedObject var player: RadioPlayerService
    @ObservedObject var equalizer: EqualizerService
    @ObservedObject var alarm: AlarmService
    @ObservedObject var lastFm: LastFmService
    @ObservedObject var diagnostics: DiagnosticsService
    @ObservedObject var sleepTimer: SleepTimerService
    @ObservedObject var hotKeys: GlobalHotKeyService
    @ObservedObject var history: TrackHistoryService
    @ObservedObject var music: MusicLibrary
    @ObservedObject var musicModel: MusicViewModel
    let updates: UpdateService
    @ObservedObject var toasts: ToastCenter

    let onClose: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ThemedRoot {
            Group {
                switch router.route {
                case .main:
                    MainView(
                        model: model,
                        library: library,
                        player: player,
                        equalizer: equalizer,
                        sleepTimer: sleepTimer,
                        toasts: toasts,
                        onOpenSettings: { router.route = .settings },
                        onOpenMusic: { router.route = .music },
                        onClose: onClose,
                        onOpenEqualizer: { router.sheet = .equalizer }
                    )
                case .music:
                    MusicView(
                        model: musicModel,
                        library: music,
                        player: player,
                        equalizer: equalizer,
                        sleepTimer: sleepTimer,
                        toasts: toasts,
                        onBack: { router.route = .main },
                        onClose: onClose,
                        onOpenEqualizer: { router.sheet = .equalizer }
                    )
                case .settings:
                    SettingsView(
                        settings: settings,
                        theme: theme,
                        equalizer: equalizer,
                        player: player,
                        alarm: alarm,
                        lastFm: lastFm,
                        diagnostics: diagnostics,
                        sleepTimer: sleepTimer,
                        hotKeys: hotKeys,
                        history: history,
                        updates: updates,
                        library: library,
                        music: music,
                        toasts: toasts,
                        onOpenMusic: { router.route = .music },
                        onBack: { router.route = .main },
                        onClose: onClose,
                        onOpenEqualizer: { router.sheet = .equalizer },
                        onOpenHistory: { router.sheet = .history },
                        onQuit: onQuit
                    )
                }
            }
            .sheet(item: $router.sheet) { sheet in
                switch sheet {
                case .equalizer:
                    EqualizerView(equalizer: equalizer) {
                        router.sheet = nil
                    }
                case .history:
                    HistoryView(history: history) {
                        router.sheet = nil
                    }
                }
            }
        }
    }
}
