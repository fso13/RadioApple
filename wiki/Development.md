# Разработка и отладка

## Структура репозитория

```
RadioMac/                 исходники приложения
  Models/                 станции, метаданные, EQ-пресеты
  Data/                   каталог станций и справка
  Services/               плеер, библиотека, метаданные, темы, автозапуск
  UI/                     SwiftUI-экраны и дизайн-система
  Window/                 статус-итем, панель, клавиатура, роутинг, debug-харнесс
  Resources/              Info.plist, entitlements, ассеты
RadioMacTests/            29 логических тестов
site/                     статический сайт для GitHub Pages
wiki/                     исходники этой вики
scripts/                  сборка, установка, генерация проекта, проверки
.github/workflows/        CI, релизы, анализ, безопасность, Pages
```

## Debug-харнесс

Только в Debug-сборке. Рендерит интерфейс в PNG и прогоняет потоки без ручных кликов.

```bash
APP=.build/DerivedData/Build/Products/Debug/RadioMac.app
"$APP/Contents/MacOS/RadioMac" -snapshot myshots
```

Снимки появятся в контейнере:

```
~/Library/Containers/com.fso13.radioMac/Data/tmp/myshots/
```

Файлы: `01-main.png`, `02-settings.png`, `03-equalizer.png`, `04-editor.png`,
`05-favorites.png`, `06-dark.png`, `07-reshown.png`, `08-playing.png`,
`09-settings-dark.png`. Харнесс сам переключает темы, открывает листы и запускает
станцию, затем завершает приложение.

`-playtest <файл>` запускает три потока (MP3, AAC, MP3) и записывает результат
проверки в файл в том же каталоге.

> На некоторых версиях macOS `open --args` не передаёт аргументы. Запускайте
> бинарник напрямую, как в примере выше.

Лог: `~/Library/Containers/com.fso13.radioMac/Data/tmp/radio-debug.log`.

## UI-система

Не хардкодьте цвета, отступы и шрифты в экранах. Используйте токены:

- `UI/Palette.swift` — семантические цвета (`textPrimary`, `separator`, `accentFill`…).
- `UI/DesignSystem.swift` — `Space`, `Radius`, `Typeface`, `PanelSurface`, `Hairline`,
  `Motion`.
- `UI/Components.swift` — шапка, кнопки, поиск, строки, тосты.

Правила стиля: монохром, крупная типографика, тонкие линии вместо карточек,
радиусы 2–4 pt, цвет только в обложках и LIVE. Тёмная тема — инверсия тех же токенов.

## Как добавить функцию

1. Модель/сервис: данные и побочные эффекты, без UI.
2. Ключ в `Preferences`, если нужно сохранение — сохранение и миграция.
3. UI: экран или компонент на токенах; не ломайте клавиатурную навигацию.
4. Перегенерируйте проект: `python3 scripts/generate_xcodeproj.py`.
5. Тесты: хотя бы логика парсинга/хранения.
6. Снимок: `-snapshot`, проверьте светлую и тёмную темы.
7. Обновите `CHANGELOG.md`, README/вики и скриншоты при необходимости.

## Тесты

```bash
xcodebuild test -project RadioMac.xcodeproj -scheme RadioMac \
  -configuration Debug -derivedDataPath .build/DerivedData \
  -destination 'platform=macOS'
```

Тесты хостятся в приложении: проверяются парсер `StreamTitle`, каталог, миграция,
`UserDefaults`, жанры и эквалайзер. Новые тесты — в `RadioMacTests/`.

## Линтеры и проверки

```bash
swiftlint lint --no-cache
actionlint
shellcheck scripts/*.sh "Install RadioMac.command"
python3 scripts/check_site.py
python3 scripts/check_wiki.py
```

- SwiftLint: ошибки валят CI, предупреждения — аннотации.
- actionlint проверяет workflow, включая shell-вставки.
- ShellCheck — скрипты сборки и лаунчер.
- `check_site.py` — ссылки/alt-тексты сайта.
- `check_wiki.py` — ссылки между страницами вики и навигацию.

## Bash 3.2

macOS-раннеры используют `/bin/bash` 3.2. Под `set -u` пустой массив нельзя
раскрывать как `"${ARR[@]}"` — только `${ARR[@]+"${ARR[@]}"}`. Это уже ломало
релизный workflow; учитывайте в новых шагах.

## Вики

Исходники вики лежат в `wiki/`. GitHub не создаёт wiki-репозиторий, пока в веб-интерфейсе
не создана первая страница, поэтому:

1. Откройте https://github.com/fso13/RadioApple/wiki.
2. Нажмите «Create the first page» (любая страница, например Home) и сохраните.
3. Опубликуйте страницы:

   ```bash
   scripts/publish_wiki.sh
   scripts/publish_wiki.sh --dry-run   # только показать изменения
   ```

Скрипт клонирует `RadioApple.wiki.git`, копирует `wiki/`, коммитит и пушит.
Проверка перед публикацией: `python3 scripts/check_wiki.py`.

## Скриншоты

1. Соберите Debug и запустите `-snapshot`.
2. Заберите нужные PNG из контейнера.
3. Конвертируйте в JPEG и положите в `site/assets/screenshots/` под теми же именами,
   которые используются в README и на сайте.

## Релиз-чеклист

- [ ] `CHANGELOG.md` содержит секцию версии.
- [ ] `swiftlint` без ошибок, тесты зелёные.
- [ ] `actionlint` и ShellCheck чистые.
- [ ] Версия в теге совпадает с `CHANGELOG`.
- [ ] Тег указывает на нужный коммит.
- [ ] После релиза проверена страница релиза и кнопка на сайте.

## Дизайн

Визуальный референс — [Office Radio app](https://dribbble.com/shots/19641552-Office-Radio-app)
(Marko Kolić / PROTOTYP). Код, графика и иконки — оригинальные; чужие ассеты не используются.
