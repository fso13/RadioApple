import SwiftUI

enum WindowRoute {
    case main
    case settings
}

enum WindowSheet: String, Identifiable {
    case equalizer

    var id: String { rawValue }
}

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
                        toasts: toasts,
                        onOpenSettings: { router.route = .settings },
                        onClose: onClose,
                        onOpenEqualizer: { router.sheet = .equalizer }
                    )
                case .settings:
                    SettingsView(
                        settings: settings,
                        theme: theme,
                        equalizer: equalizer,
                        library: library,
                        toasts: toasts,
                        onBack: { router.route = .main },
                        onClose: onClose,
                        onOpenEqualizer: { router.sheet = .equalizer },
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
                }
            }
        }
    }
}
