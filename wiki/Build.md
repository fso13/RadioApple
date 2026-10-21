# Сборка

## Требования

- macOS 14+.
- Xcode 16.4 или новее (Swift 6 language mode; проверено на Xcode 27 / Swift 6.4).
- Apple Silicon или Intel.
- Для установщиков: Python 3 и сеть (dmgbuild ставится автоматически).

## Клонирование и запуск

```bash
git clone https://github.com/fso13/RadioApple.git
cd RadioApple
open RadioMac.xcodeproj
```

В Xcode выберите схему **RadioMac**, цель **My Mac** и нажмите **Run** (⌘R).
Приложение появится в меню-баре. Для отладки можно запускать из Xcode — тогда видны
логи и работает отладочный харнесс.

### Без Xcode

```bash
xcodebuild -project RadioMac.xcodeproj -scheme RadioMac \
  -configuration Debug -derivedDataPath .build/DerivedData build

open .build/DerivedData/Build/Products/Debug/RadioMac.app
```

## Тесты

```bash
xcodebuild test -project RadioMac.xcodeproj -scheme RadioMac \
  -configuration Debug -derivedDataPath .build/DerivedData \
  -destination 'platform=macOS'
```

18 логических тестов: парсер метаданных, каталог, миграция, хранилище, жанры, эквалайзер,
группы/порядок станций, информация о потоке, расписание будильника и диагностика.
Тесты запускаются в host-приложении, поэтому окно и статус-итем создаются, но это
не влияет на результат.

## Регенерация проекта

`RadioMac.xcodeproj` генерируется из файлов на диске:

```bash
python3 scripts/generate_xcodeproj.py
```

Добавили новый `.swift` — перегенерируйте проект. CI проверяет, что проект в репозитории
совпадает с результатом генератора.

## Release и универсальная сборка

```bash
xcodebuild -project RadioMac.xcodeproj -scheme RadioMac \
  -configuration Release -derivedDataPath .build/DerivedData \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

`MARKETING_VERSION` и `CURRENT_PROJECT_VERSION` можно переопределить:

```bash
xcodebuild ... MARKETING_VERSION=1.2.0 CURRENT_PROJECT_VERSION=42 build
```

Версия в `Info.plist` подставляется из этих настроек, поэтому она совпадает
с именем DMG и тегом релиза.

## Установщики

```bash
scripts/make_installer.sh                 # Release + DMG + PKG
scripts/make_installer.sh --skip-build    # упаковать уже собранное
scripts/make_installer.sh --version 1.1.0
```

Скрипт:

1. Проверяет SHA-256 вендорных библиотек (`scripts/verify_third_party.sh`).
2. Собирает Release (если не `--skip-build`).
3. Готовит `.app`, подписывает dylib и приложение (ad-hoc или Developer ID).
4. Рисует окно DMG через dmgbuild, ставит фон, иконки и иконку тома.
5. Собирает PKG и контрольные суммы в `dist/`.

Python-инструменты закреплены в `scripts/requirements-installer.txt`; venv создаётся
в `.build/tools/dmgbuild-venv`. Если сети нет, DMG соберётся без фона.

### Подпись

```bash
export CODESIGN_IDENTITY="Developer ID Application: Имя (TEAMID)"
export CODESIGN_INSTALLER_IDENTITY="Developer ID Installer: Имя (TEAMID)"
scripts/make_installer.sh --skip-build
```

Скрипт подписывает с `--options runtime --timestamp` и проверяет подпись.
Для нотарификации:

```bash
xcrun notarytool submit dist/RadioMac-1.0.0.dmg \
  --apple-id "you@example.com" --team-id TEAMID \
  --password "app-specific-password" --wait
xcrun stapler staple dist/RadioMac-1.0.0.dmg
```

После stapling пересчитайте `SHA256SUMS.txt`: файл изменился.

### App Groups

Виджет (RM-19) и iCloud (RM-18) используют `com.apple.security.application-groups`.
Это entitlement требует provisioning profile с App Groups: ad-hoc подпись падает с
`"RadioMac" requires a provisioning profile`. Для локальной проверки нужен Apple
Development team, для релиза — Developer ID с профилем, где зарегистрирован
`group.com.fso13.radioMac`.

## Локальный лаунчер

`Install RadioMac.command` собирает приложение, ставит его в `/Applications`,
снимает карантин и запускает. Удобно для локальной проверки «как у пользователя».
Требует права записи в `/Applications` (или используйте `scripts/install.sh`).

## Отладка сборки

- Ошибки SwiftUI-макросов (`swift-plugin-server`) обычно означают, что сборка идёт
  в ограниченной среде; собирайте через Xcode или `xcodebuild`.
- `ThirdParty/BASS` должен лежать рядом с проектом: пути заданы относительно
  `PROJECT_DIR`.
- Если Xcode просит команду разработчика, проверьте **Settings → Accounts** и
  **Signing & Capabilities**. Для локальной сборки достаточно ad-hoc подписи.

Дальше: [CI/CD и релизы](CICD), [Разработка и отладка](Development).
