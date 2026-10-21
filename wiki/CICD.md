# CI/CD и релизы

Все пайплайны живут в `.github/workflows`. Сборка и тесты идут на `macos-15`,
вспомогательные проверки — на Ubuntu.

## Workflow

| Файл | Триггер | Что делает |
| --- | --- | --- |
| `ci.yml` | push/PR в `main` | Debug-сборка, 13 тестов, `xcresult` при падении |
| `distribute.yml` | push в `main`, вручную | universal Release, DMG + PKG как артефакты |
| `release.yml` | тег `v*`, вручную | сборка, подпись, нотарификация, SBOM, GitHub Release |
| `lint.yml` | push/PR | SwiftLint, actionlint, ShellCheck, сверка `.xcodeproj`, сайт и вики |
| `codeql.yml` | push/PR, расписание | CodeQL для Swift |
| `security.yml` | push/PR, расписание | OSV-Scanner, Dependency Review, SBOM + Grype, SHA-256 BASS |
| `pages.yml` | изменения в `site/` | публикация сайта на GitHub Pages |

## CI

`ci.yml` собирает Debug и запускает XCTest. Если тесты падают, `xcresult` уходит
артефактом. Перед сборкой проверяются SHA-256 вендорных библиотек.

## Сборка дистрибутива

`distribute.yml` на каждый push в `main` собирает universal Release и упаковывает
DMG и PKG в артефакт `RadioMac-distribution` (хранится 14 дней). Это проверка того,
что установщик собирается, а не публикация релиза.

## Релиз

1. Добавьте в `CHANGELOG.md` секцию версии:

   ```markdown
   ## [1.2.0] — 2026-12-01

   ### Добавлено
   - ...
   ```

2. Поставьте тег и отправьте:

   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```

3. `release.yml` соберёт приложение с `MARKETING_VERSION=1.2.0`, упакует DMG/PKG,
   подпишет и нотарифицирует (если настроены секреты), сгенерирует SBOM и создаст
   GitHub Release с заметками и ссылками на скачивание.

Ручной запуск: **Actions → Release → Run workflow**, версия без `v` (`1.2.0`).
Workflow создаст тег, если его ещё нет.

### Что попадает в заметки

`scripts/release_notes.py` берёт секцию из `CHANGELOG.md` и добавляет ссылки:

- `RadioMac-<версия>.dmg`
- `RadioMac-<версия>.pkg`
- `SHA256SUMS.txt`
- `RadioMac-<версия>.spdx.json`

Если секции нет, в заметки попадёт ссылка на сравнение с предыдущим тегом.
Ссылки на скачивание есть всегда.

### Подпись и нотарификация

Без секретов релиз собирается ad-hoc, и в заметках это указывается. Для Developer ID
добавьте в *Settings → Secrets and variables → Actions*:

| Секрет | Назначение |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `.p12` с сертификатами Developer ID Application/Installer |
| `P12_PASSWORD` | пароль `.p12` |
| `KEYCHAIN_PASSWORD` | пароль временной keychain |
| `DEVELOPER_ID_APPLICATION` | `Developer ID Application: Имя (TEAMID)` |
| `DEVELOPER_ID_INSTALLER` | `Developer ID Installer: Имя (TEAMID)` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | нотарификация `notarytool` |

Сертификат импортируется во временную keychain только на время job.
PKG нотарифицируется только при наличии `DEVELOPER_ID_INSTALLER`.

### Повторный запуск и теги

- «Re-run jobs» использует **ту же** версию workflow, которая была в упавшем запуске.
  После исправления workflow нужен новый запуск.
- Если тег уже существует и указывает на другой коммит, workflow предупредит.
  Перед публикацией релиза тег лучше перенести на нужный коммит или удалить и дать
  workflow создать его заново.
- Существующий релиз обновляется: ассеты перезаписываются, заметки и заголовок
  обновляются.

### Особенность Bash 3.2

На macOS-раннерах `/bin/bash` — версия **3.2**. Пустой массив под `set -u`
нельзя раскрывать как `"${ARR[@]}"` — будет `unbound variable`. В workflow
используется безопасная форма `${ARR[@]+"${ARR[@]}"}`. Учитывайте это в новых шагах.

## GitHub Pages

Сайт лежит в `site/` и публикуется `pages.yml`. Один раз включите
**Settings → Pages → Build and deployment → Source: GitHub Actions**.

- URL: `https://fso13.github.io/RadioApple/`.
- Кнопка «Скачать» подтягивает последний релиз через GitHub API, поэтому сайт
  не нужно пересобирать после релиза.
- Локальный просмотр: `scripts/preview_site.sh` (http://127.0.0.1:8000).

## Зависимости

Dependabot обновляет GitHub Actions и Python-инструменты (`scripts/requirements-*.txt`).
Python-версии закреплены, чтобы сборка установщика была воспроизводимой.

## Локальные проверки

```bash
actionlint
shellcheck scripts/*.sh "Install RadioMac.command"
swiftlint lint --no-cache
python3 scripts/check_site.py
python3 scripts/check_wiki.py
```

`swiftlint` настроен в `.swiftlint.yml`: предупреждения не валят сборку,
ошибки — валят. CI дополнительно проверяет, что `.xcodeproj` совпадает с генератором.

## Секреты и безопасность

Секреты не попадают в артефакты; сертификат удаляется после импорта. Подробнее —
[Безопасность](Security). Сами проверки CVE и SBOM описаны там же.
