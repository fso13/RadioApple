import SwiftUI

/// Four tabs — radio, the Radio Browser directory, local music, settings —
/// with the mini player docked above the tab bar on every screen.
struct RootView: View {
    @EnvironmentObject private var environment: IOSEnvironment
    @EnvironmentObject private var router: IOSRouter
    @EnvironmentObject private var theme: ThemeService
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: AppPalette {
        switch theme.preference {
        case .system: return AppPalette.resolved(for: systemScheme)
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        TabView(selection: $router.screen) {
            RadioScreen(model: environment.mainModel, showPlayer: $router.showPlayer)
                .tabItem {
                    Label("Радио", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(IOSRouter.Screen.radio)

            BrowserScreen(showPlayer: $router.showPlayer)
                .tabItem {
                    Label("Каталог", systemImage: "magnifyingglass")
                }
                .tag(IOSRouter.Screen.browser)

            MusicScreen(model: environment.musicModel, showPlayer: $router.showPlayer)
                .tabItem {
                    Label("Музыка", systemImage: "music.note")
                }
                .tag(IOSRouter.Screen.music)

            SettingsScreen(showPlayer: $router.showPlayer)
                .tabItem {
                    Label("Настройки", systemImage: "slider.horizontal.3")
                }
                .tag(IOSRouter.Screen.settings)
        }
        .tint(palette.textPrimary)
        .sensoryFeedback(.selection, trigger: router.screen)
        .environment(\.palette, palette)
        .preferredColorScheme(theme.preference.colorScheme)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .sheet(isPresented: $router.showPlayer) {
            NowPlayingScreen(model: environment.mainModel)
                .environmentObject(environment.player)
                .environmentObject(environment.library)
                .environmentObject(environment.equalizer)
                .environment(\.palette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(palette.window)
        }
    }
}
