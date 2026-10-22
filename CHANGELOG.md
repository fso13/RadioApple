# Changelog

Все заметные изменения проекта. Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
версии — [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

## [1.3.1] — 2026-10-22

### Исправлено

- Индикатор таймера сна в меню-баре обновляется каждую секунду.

## [1.3.0] — 2026-10-22

### Добавлено

- Таймер сна 15/30/60/90 минут с пятисекундным затуханием, индикатором в
  PlayerBar и меню-баре, отменой.
- Настраиваемые глобальные горячие клавиши play/pause и следующей станции
  на Carbon; проверка системных конфликтов и работа при скрытом окне.
- Локальная история последних 100 треков: поиск, копирование, очистка,
  станция и время; доступ из настроек и меню-бара.
- String Catalog ru/en, VoiceOver-метки, Reduce Motion и UI-аудит доступности.

## [1.2.1] — 2026-10-21

### Исправлено

- Sparkle 2 в sandbox: включён `SUEnableInstallerLauncherService` и добавлены
  mach-lookup исключения `com.fso13.radioMac-spks`/`-spki`. Установщик обновлений
  снова запускается; первая установка 1.2.1 с 1.1.0 выполняется вручную, потому
  что в 1.1.0 этих ключей ещё не было.

## [1.2.0] — 2026-10-21

### Добавлено

- Виджет macOS 14+ с текущей станцией/треком и play/pause.
- Элемент Control Center macOS 26+ «RadioMac» (play/pause).
- Общее состояние виджета через `/Users/Shared/RadioMac/nowplaying.json`
  и sandbox temporary-exception; App Group и Developer team не требуются.

## [1.1.0] — 2026-10-21

### Добавлено

- Sparkle 2: appcast, EdDSA-подпись, проверка обновлений в приложении и CI,
  публикация appcast в latest release.
- App Intents/Shortcuts («Играть станцию», «Пауза», «Открыть RadioMac») и URL-схема
  `radiomac://play/<id>`, `radiomac://pause`, `radiomac://open`.
- Radio Browser: поиск по названию/жанру/стране, превью, добавление в библиотеку
  и защита от дублей по URL/`stationuuid`.
- Импорт/экспорт JSON, M3U и OPML с drag-and-drop, режимами add/replace и
  сохранением избранного.
- Настройки на станцию: смещение громкости в dB, EQ-пресет и автозапуск.
- Мини-плеер в меню-баре: обложка, трек, play/pause, громкость и быстрый выбор станции.
- XCUITest главного сценария/настроек и светлые/тёмные снапшоты в CI.
- Панель потока: кодек, битрейт, частота, каналы, буфер, сервер и копирование диагностики.
- Виджет macOS 14+ и элемент Control Center macOS 26+ с текущей станцией и play/pause;
  общее состояние через sandbox temporary-exception без App Group.
- Группы станций, будильник-радио, локальная диагностика и Last.fm
  (now-playing/scrobble с ключами из GitHub Secrets).
- Homebrew Cask: tap `fso13/tap`, установка `brew install --cask radiomac`.
- Flutter-исходники убраны из `main`; версия сохранена в ветке `flutter-legacy`
  и теге `flutter-legacy-1.0`.

### Изменено

- Audio engine: AVPlayer для HLS, AAC и MP3; нативный EQ через `MTAudioProcessingTap`.
- Swift 6: strict concurrency complete, аудит `@MainActor`/`Sendable`,
  предупреждения компилятора считаются ошибками.
- CodeQL переведён на autobuild без Flutter-проекта.
- Обновлены release-скрипты: Sparkle-подпись, appcast и проверка feed/key в CI.

### Удалено

- BASS, BASS_FX и BASS_AAC, вендорные dylib/заголовки и bridging header.
- Flutter-приложение из `main` (сохранено в `flutter-legacy`).

### Исправлено

- HLS timed metadata и ICY side-channel.
- Автопереподключение с backoff 1/2/5/10 с, лимитом попыток и ручным retry.
- Нативный EQ AVPlayer для HLS/AAC/MP3.
- Панель потока получает реальные параметры AVPlayer; копирование диагностики.

### Безопасность

- Pillow обновлён до 13.0.0: закрыты advisories OSV, затрагивавшие 12.3.0.
  Инструмент используется только для генерации иконок и фона установщика.

## [1.0.1] — 2026-10-21

### Добавлено

- GitHub Actions: CI с тестами, сборка дистрибутива, релизы с заметками и GitHub Pages.
- Статический анализ: SwiftLint, CodeQL, actionlint, ShellCheck и проверка
  синхронности Xcode-проекта.
- CVE-проверки: OSV-Scanner, Dependency Review, SBOM + Grype, Dependabot
  и SHA-256 вендорных BASS-библиотек.
- Статический сайт с автоподстановкой последнего релиза и локальным превью.

### Исправлено

- Релизный workflow: совместимость с Bash 3.2 (пустые массивы), обновление
  существующего релиза и заметки со ссылками на скачивание.
- Справка приведена к новой навигации, транспорту и эквалайзеру.

## [1.0.0] — 2026-10-21

### Добавлено

- Нативная версия RadioMac на Swift / SwiftUI + AppKit: меню-бар, безрамочная панель,
  клавиатурные шорткаты, Now Playing в Control Center.
- Новый редакционный интерфейс: монохромная палитра, крупная навигация по жанрам,
  таблица станций, нижний транспорт, тёмная тема как инверсия светлой.
- Переключение на предыдущую/следующую станцию, запуск первой станции кнопкой Play.
- Каталог из 47 станций, свои станции, избранное, поиск, восстановление каталога.
- Метаданные трека: ICY, Icecast, SomaFM, Radio Paradise, обложки iTunes.
- Автозапуск через `SMAppService`, миграция настроек из Flutter-версии.
- Фирменная иконка приложения, фон установщика и окно DMG с перетаскиванием.

### Изменено

- Приложение переписано с Flutter на Swift; Flutter-исходники сохранены в репозитории
  для сравнения.
- Окно увеличено до 780×660 под двухколоночную раскладку.

### Ограничения

- `libbass_fx.dylib` из поставки не загружается на macOS 27 / Apple Silicon: эквалайзер
  показывает предупреждение, настройки сохраняются.
- `libbass_aac.dylib` собран только под x86_64; AAC-потоки играют через CoreAudio.
- HLS-поток `SOUNDPARK DEEP` остаётся неиграбельным (BASS не поддерживает HLS).

[Unreleased]: https://github.com/fso13/RadioApple/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/fso13/RadioApple/releases/tag/v1.3.1
[1.3.0]: https://github.com/fso13/RadioApple/releases/tag/v1.3.0
[1.2.1]: https://github.com/fso13/RadioApple/releases/tag/v1.2.1
[1.2.0]: https://github.com/fso13/RadioApple/releases/tag/v1.2.0
[1.1.0]: https://github.com/fso13/RadioApple/releases/tag/v1.1.0
[1.0.1]: https://github.com/fso13/RadioApple/releases/tag/v1.0.1
[1.0.0]: https://github.com/fso13/RadioApple/releases/tag/v1.0.0
