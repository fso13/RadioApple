# Безопасность

## Поддерживаемые версии

| Версия | Поддержка |
| --- | --- |
| 1.x | да |
| < 1.0 | нет |

## Как сообщить об уязвимости

Не открывайте публичный issue. Используйте приватный
[GitHub Security Advisory](https://github.com/fso13/RadioApple/security/advisories/new)
или напишите мейнтейнеру. Укажите версию, macOS, шаги воспроизведения и оценку влияния.
Ответ — в течение 5 рабочих дней.

## Зависимости

- Пакетных менеджеров в рантайме нет: только системные фреймворки macOS.
- Внешних аудиобиблиотек нет: аудио идёт через системный AVFoundation/AVPlayer.
- Python-инструменты сборки закреплены: `scripts/requirements-installer.txt` (dmgbuild)
  и `scripts/requirements-dev.txt` (Pillow). Обновления приходят через Dependabot.

## Автоматические проверки

| Проверка | Где | Что делает |
| --- | --- | --- |
| CodeQL (`swift`) | `.github/workflows/codeql.yml` | семантический анализ кода |
| SwiftLint | `.github/workflows/lint.yml` | статический анализ стиля и ошибок |
| actionlint | `.github/workflows/lint.yml` | проверка workflow-файлов |
| OSV-Scanner | `.github/workflows/security.yml` | уязвимости в зависимостях (OSV.dev) |
| SBOM + Grype | `.github/workflows/security.yml` | SBOM приложения и скан известных CVE (critical) |
| Dependency Review | `.github/workflows/security.yml` | блокировка PR с уязвимыми зависимостями |
| Dependabot | `.github/dependabot.yml` | обновления actions и pip-инструментов |
| Аудио | AVFoundation | системный AVPlayer без сторонних бинарников |

SBOM публикуется как артефакт релиза (`RadioMac-<версия>.spdx.json`). Он описывает
само приложение и его компоненты; системные фреймворки Apple не индексируются OSV/NVD,
поэтому для них действует контроль SHA-256 и ручная проверка обновлений un4seen.
Результаты сканов загружаются в *Security → Code scanning*.

## Релизы

Релиз создаётся только из тега `v*` workflow `.github/workflows/release.yml`:
сборка → подпись (если настроены секреты) → нотарификация → SBOM → GitHub Release
с DMG, PKG и контрольными суммами. Ad-hoc сборка не нотарифицируется — в заметках к релизу
это указывается.

## Last.fm

Скробблинг выключен по умолчанию. API-ключи и сессия Last.fm хранятся в Keychain;
запросы уходят только на `ws.audioscrobbler.com` после явного включения и
авторизации. Ключи можно удалить в настройках.

## Диагностика

Краш-репорты не отправляются. Пользователь может включить локальный журнал в
настройках: записи лежат в контейнере приложения, URL обрезаются до домена,
данные не покидают Mac. Журнал можно просмотреть, скопировать и очистить.

## Секреты

Подпись и нотарификация включаются только при наличии секретов:
`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`,
`DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_INSTALLER`,
`APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`.
Секреты не попадают в артефакты; сертификат импортируется во временную keychain.
