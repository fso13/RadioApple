# Архитектура

RadioMac — нативное приложение на **Swift 6** (SwiftUI + AppKit, strict concurrency), без внешних
пакетных зависимостей. Аудио: AVPlayer для HLS/AAC/MP3, ICY side-channel и
нативный EQ через `MTAudioProcessingTap`; внешних аудиобиблиотек нет.

## Слои

```
┌─────────────────────────────────────────────┐
│ AppKit: NSStatusItem, NSPanel, NSEvent      │
├─────────────────────────────────────────────┤
│ SwiftUI: MainView, Settings, EQ, Editor     │
├─────────────────────────────────────────────┤
│ AppEnvironment + MainViewModel / Router     │
├─────────────────────────────────────────────┤
│ Services: player, library, EQ, metadata,    │
│ logos, now playing, theme, login item       │
├─────────────────────────────────────────────┤
│ NativeAudioEngine (AVPlayer), UserDefaults   │
└─────────────────────────────────────────────┘
```

## Запуск и окно

- `RadioMacApp` — `@main`, ручной запуск `NSApplication` с `AppDelegate`, accessory-режим.
- `AppDelegate` создаёт `AppEnvironment`, `StatusItemController` и `MainWindowController`.
- `Info.plist` содержит `LSUIElement = true`: приложение не показывается в Dock и Cmd+Tab.
- `MainWindowController` держит безрамочный `NSPanel` (780×660) с `NSHostingView`.
  Панель может становиться key, чтобы работали текстовые поля и шорткаты; прозрачный фон
  и внутренний отступ 10 pt дают «страницу» с тенью.
- Перетаскивание — за область шапки; закрытие окна скрывает панель, но не останавливает эфир.
- `KeyboardRouter` — локальный монитор `NSEvent`, поэтому однобуквенные шорткаты
  не конфликтуют с вводом в поиске и форме.

## Сервисы

| Сервис | Ответственность |
| --- | --- |
| `NativeAudioEngine` | AVPlayer, ICY, HLS-метаданные, стоп/пауза, EQ tap |
| `NativeEqualizer` | 10-полосный Biquad DSP для audio tap AVPlayer |
| `NativeAudioEngine` | AVPlayer для HLS/AAC: play/pause/stop, громкость, KVO-состояния |
| `ICYMetadataReader` | side-channel ICY `StreamTitle` для прогрессивных AVPlayer-потоков |
| `HLSMetadataDelegate` | HLS timed metadata через `AVPlayerItemMetadataOutput` |
| `ReconnectPolicy` | backoff 1/2/5/10 с и лимит попыток |
| `RadioPlayerService` | состояние плеера, громкость, опрос метаданных, Now Playing |
| `StationLibrary` | каталог, избранное, добавление/удаление, логотипы, персистентность |
| `EqualizerService` | полосы, пресеты, дебаунс записи |
| `NowPlayingLookup` | Radio Paradise, SomaFM, Icecast, ICY, обложки iTunes |
| `LogoResolver` | Radio Browser, сайт станции, favicon |
| `NowPlayingCenter` | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| `Preferences` | ключи `UserDefaults` |
| `AppSettings` | громкость, автозапуск, последняя станция |
| `ThemeService` | системная/светлая/тёмная тема |
| `LaunchAtLogin` | `SMAppService.mainApp` |
| `AlarmService` | расписание будильника, fade-in, уведомления, wake catch-up |
| `DiagnosticsService` | opt-in локальный журнал и обнаружение аварийных завершений |
| `LastFmService` | opt-in Last.fm OAuth, now-playing, scrobble, Keychain |
| `AppRuntime` / `RadioIntents` | App Intents, Shortcuts и URL-команды к библиотеке/плееру |
| `RadioBrowserService` | поиск Radio Browser, пагинация и модель станции |
| `RadioBrowserView` | превью и добавление найденных станций без дублей |
| `StationTransfer` | JSON/M3U/OPML, импорт и экспорт |
| `StationTransferView` | файлы, drag-and-drop и режим добавления/замены |
| `UpdateService` | Sparkle 2, проверка appcast и установка обновлений |
| `MiniPlayerView` | поповер меню-бара: обложка, транспорт, громкость, станции |
| `SharedPlaybackState` | общий JSON состояния для WidgetKit |
| `RadioMacWidget` | виджет macOS 14+ и Control Center macOS 26+ |
| `SleepTimerService` | таймер сна и пятисекундное затухание |
| `GlobalHotKeyService` | Carbon play/pause и следующая станция |
| `TrackHistoryService` | последние 100 треков локально |
| `MusicLibrary` | локальная музыка: папки-источники, теги, альбомы, исполнители, плейлисты, обложки, M3U, обогащение |
| `LocalAudioMetadata` | теги и обложки из файлов через AVFoundation, кэш обложек |
| `MusicPlaylistFile` | импорт и экспорт M3U/M3U8 для локальных файлов |
| `MetadataEnrichmentService` | нормализация, оценка совпадений и кэш запросов |
| `MetadataProviders` | Apple Music (iTunes Search) и Deezer |

`AppEnvironment` собирает сервисы и UI-состояние (`MainViewModel`, `WindowRouter`).
`MainViewModel` фильтрует список, хранит поиск, выделение, открытые листы и тосты.

## Потоки

- Проект собирается в **Swift 6** с `SWIFT_STRICT_CONCURRENCY = complete` и
  `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
- UI, модели состояния и сервисы изолированы `@MainActor`. `NativeAudioEngine`
  владеет AVPlayer; его callbacks и метаданные возвращаются в UI через
  `Task { @MainActor in ... }`.
- `NowPlayingLookup` и `LogoResolver` помечены `@unchecked Sendable`: их кэши
  используются только из асинхронных задач плеера/библиотеки.
- `MetadataEnrichmentService` — `@unchecked Sendable` с `NSLock` для кэша; оба
  онлайн-каталога опрашиваются параллельно в `TaskGroup`.
- Теги локальных файлов читаются вне main-актора батчами по 6 файлов;
  `MusicLibrary` обновляет прогресс между батчами.
- EQ-буферы AVPlayer обрабатываются в realtime-колбэке без аллокаций.
- AVPlayer живёт на главном акторе; его KVO-состояния приходят через `Task { @MainActor in }`.
- `RadioPlayerService` всегда использует AVPlayer; отдельной настройки движка нет.
- При ошибке или неожиданном `idle` включается `ReconnectPolicy`; после 10 секунд
  стабильного эфира счётчик попыток сбрасывается.
- AVPlayer не отдаёт ICY: для `.aac`/`.mp3` открывается второй запрос с
  `Icy-MetaData: 1`, аудио отбрасывается, `StreamTitle` уходит в Now Playing.
- Результаты и ICY-метаданные приходят в UI на main-акторе.
- Метаданные и обложки загружаются асинхронно (`URLSession`, `async/await`),
  с проверкой поколения, чтобы ответ старой станции не перетёр новый трек.
- Опрос метаданных — таймер раз в 20 секунд; отменяется при остановке.
- Локальные файлы играет тот же AVPlayer по `file://`-URL: ICY и HLS-метаданные
  для них отключаются, а длительность и позиция читаются из `AVPlayer`.
  По окончании трека `onEnded` переключает очередь `localQueue` или завершает
  воспроизведение.

## Данные

`UserDefaults` (контейнер песочницы):

| Ключ | Значение |
| --- | --- |
| `stations_v1` | JSON станций (включая `isFavorite`) |
| `volume`, `last_station_id` | громкость и последняя станция |
| `resume_last_station`, `auto_start` | поведение |
| `theme_preference` | тема |
| `eq_enabled`, `eq_preset`, `eq_gains`, `eq_custom_gains` | эквалайзер |
| `alarm_settings` | расписание будильника |
| `diagnostics_enabled` | согласие на локальный журнал |
| `lastfm_enabled` | согласие на Last.fm |
| `audio_engine` | удалён: всегда AVPlayer |
| `music_auto_enrich` | автоматическое обогащение новых локальных треков |
| `music_sort_order` | выбранная сортировка локальной музыки |

Станции кодируются Codable с ключом `logoUrl`; формат хранения стабилен между версиями.

Треки, плейлисты, выбранные обложки исполнителей и закладки доступа лежат в
`Application Support/RadioMac/music-library.json`, обложки — в
`Caches/RadioMac/Artwork/`; в `UserDefaults` хранятся только настройки вроде
автообогащения и выбранной сортировки. Файлы на диске не изменяются.

## UI и дизайн-система

| Файл | Что задаёт |
| --- | --- |
| `UI/Palette.swift` | монохромная семантическая палитра (свет/тьма) |
| `UI/DesignSystem.swift` | отступы, радиусы, шкала шрифтов, панель, хайрлайны |
| `UI/Components.swift` | шапка, кнопки, поиск, строки, тосты |
| `UI/MainView.swift` | главная страница |
| `UI/Sidebar.swift` | жанры и обложка |
| `UI/StationRow.swift` | строка таблицы |
| `UI/PlayerBar.swift` | нижний транспорт |
| `UI/MusicView.swift`, `UI/MusicViewPages.swift`, `UI/MusicViewSidebar.swift` | страница локальной музыки, навигация, альбомы, исполнители и плейлисты |
| `UI/MusicViewReorder.swift` | перетаскивание строк и сохранение своего порядка |
| `UI/MusicPages.swift`, `UI/MusicTrackRow.swift` | карточки коллекций, страницы альбомов и исполнителей, строка трека |
| `UI/MusicArtworkEditorView.swift` | обложка из сети, файла или ссылки |
| `UI/MusicTrackEditorView.swift`, `UI/MusicSourcesView.swift`, `UI/MusicPlaylistPromptView.swift` | метаданные, источники, имя плейлиста |
| `UI/SettingsView.swift`, `HelpView.swift`, `EqualizerView.swift`, `StationEditorView.swift` | страницы и листы |
| `UI/BrandMark.swift`, `StationLogo.swift`, `ImageCache.swift` | бренд, обложки, кэш |

Принципы: одна краска (чернила), крупная типографика, тонкие линии вместо карточек,
радиусы 2–4 pt (панель — 12 pt), цвет только в обложках и LIVE.

## Безопасность

- App Sandbox включён; сетевые права — только исходящие соединения.
- Локальная музыка читается через `NSOpenPanel` (`files.user-selected.read-only`)
  и security-scoped закладки (`files.bookmarks.app-scope`); доступ можно отозвать
  в «Источниках».
- Запись — только в контейнер `~/Library/Containers/com.fso13.radioMac/`.
- Нет аккаунтов, телеметрии и сторонних SDK.
- Вендорные dylib подписываются вместе с приложением и проверяются по SHA-256.

## Исходники

- [RadioMacApp.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/RadioMacApp.swift)
- [AppDelegate.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/AppDelegate.swift)
- [MainWindowController.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Window/MainWindowController.swift)
- [NativeAudioEngine.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Services/NativeAudioEngine.swift)
- [RadioPlayerService.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Services/RadioPlayerService.swift)
- [MusicLibrary.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Services/MusicLibrary.swift)
- [LocalAudioMetadata.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Services/LocalAudioMetadata.swift)
- [MetadataEnrichment.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Services/MetadataEnrichment.swift)
