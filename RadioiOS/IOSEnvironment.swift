import Combine
import Foundation

/// Services shared by the iPhone screens.
///
/// It mirrors the macOS `AppEnvironment`, minus everything that only makes
/// sense on a desktop: menu-bar item, global hotkeys, launch-at-login, Sparkle
/// updates, the alarm and the sleep timer.
@MainActor
final class IOSEnvironment: ObservableObject {
    let settings: AppSettings
    let theme: ThemeService
    let library: StationLibrary
    let music: MusicLibrary
    let equalizer: EqualizerService
    let player: RadioPlayerService
    let mainModel: MainViewModel
    let musicModel = MusicViewModel()

    init() {
        settings = AppSettings()
        theme = ThemeService()
        library = StationLibrary()
        music = MusicLibrary()
        equalizer = EqualizerService()
        player = RadioPlayerService(settings: settings, library: library, equalizer: equalizer)
        mainModel = MainViewModel(library: library)

        library.load()
        music.load()
        player.start()
    }
}
