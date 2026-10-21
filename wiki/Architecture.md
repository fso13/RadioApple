# Архитектура

RadioMac — нативное приложение на **Swift 6** (SwiftUI + AppKit, strict concurrency), без внешних
пакетных зависимостей. Аудио: BASS 2.4 для MP3/AAC/ICY/EQ, AVPlayer — для HLS;
вендорные библиотеки лежат в `ThirdParty/BASS`.

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
│ RadioEngine (BASS), UserDefaults, сеть      │
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
| `RadioEngine` | единственный владелец BASS-хэндлов, потоки, ICY, стоп/пауза, EQ |
| `NativeAudioEngine` | AVPlayer для HLS: play/pause/stop, громкость, KVO-состояния |
| `RadioPlayerService` | состояние плеера, громкость, опрос метаданных, Now Playing |
| `StationLibrary` | каталог, избранное, добавление/удаление, логотипы, персистентность |
| `EqualizerService` | полосы, пресеты, дебаунс записи |
| `NowPlayingLookup` | Radio Paradise, SomaFM, Icecast, ICY, обложки iTunes |
| `LogoResolver` | Radio Browser, сайт станции, favicon |
| `NowPlayingCenter` | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| `Preferences` | ключи `UserDefaults` и миграция из Flutter |
| `AppSettings` | громкость, автозапуск, последняя станция |
| `ThemeService` | системная/светлая/тёмная тема |
| `LaunchAtLogin` | `SMAppService.mainApp` |
| `AlarmService` | расписание будильника, fade-in, уведомления, wake catch-up |
| `DiagnosticsService` | opt-in локальный журнал и обнаружение аварийных завершений |
| `LastFmService` | opt-in Last.fm OAuth, now-playing, scrobble, Keychain |

`AppEnvironment` собирает сервисы и UI-состояние (`MainViewModel`, `WindowRouter`).
`MainViewModel` фильтрует список, хранит поиск, выделение, открытые листы и тосты.

## Потоки

- Проект собирается в **Swift 6** с `SWIFT_STRICT_CONCURRENCY = complete` и
  `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
- UI, модели состояния и сервисы изолированы `@MainActor`. `RadioEngine` —
  единственный nonisolated остров: он владеет последовательной `workQueue` и
  помечен `@unchecked Sendable`; BASS-колбэки возвращаются в UI через
  `Task { @MainActor in ... }`.
- `NowPlayingLookup` и `LogoResolver` помечены `@unchecked Sendable`: их кэши
  используются только из асинхронных задач плеера/библиотеки.
- BASS вызывается только на последовательной `workQueue` — никаких гонок за хэндлы.
- AVPlayer живёт на главном акторе; его KVO-состояния приходят через `Task { @MainActor in }`.
- `RadioPlayerService` выбирает движок по настройке `audio_engine` и URL: `.m3u8` → AVPlayer.
- Результаты и ICY-метаданные приходят в UI на main-акторе.
- Метаданные и обложки загружаются асинхронно (`URLSession`, `async/await`),
  с проверкой поколения, чтобы ответ старой станции не перетёр новый трек.
- Опрос метаданных — таймер раз в 20 секунд; отменяется при остановке.

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
| `audio_engine` | automatic / bass / native |
| `native_migration_v1` | флаг миграции из Flutter |

Станции кодируются Codable с ключами Flutter-версии (`logoUrl`), поэтому данные
совместимы. Миграция копирует `flutter.*` → нативные ключи один раз и не перетирает
новые значения.

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
| `UI/SettingsView.swift`, `HelpView.swift`, `EqualizerView.swift`, `StationEditorView.swift` | страницы и листы |
| `UI/BrandMark.swift`, `StationLogo.swift`, `ImageCache.swift` | бренд, обложки, кэш |

Принципы: одна краска (чернила), крупная типографика, тонкие линии вместо карточек,
радиусы 2–4 pt (панель — 12 pt), цвет только в обложках и LIVE.

## Безопасность

- App Sandbox включён; сетевой клиент — единственное сетевое право.
- Запись — только в контейнер `~/Library/Containers/com.fso13.radioMac/`.
- Нет аккаунтов, телеметрии и сторонних SDK.
- Вендорные dylib подписываются вместе с приложением и проверяются по SHA-256.

## Исходники

- [RadioMacApp.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/RadioMacApp.swift)
- [AppDelegate.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/AppDelegate.swift)
- [MainWindowController.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Window/MainWindowController.swift)
- [RadioEngine.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Services/RadioEngine.swift)
- [RadioPlayerService.swift](https://github.com/fso13/RadioApple/blob/main/RadioMac/Services/RadioPlayerService.swift)
