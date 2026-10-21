# RadioMac

**Интернет-радио в меню-баре macOS.** Нативное приложение на Swift / SwiftUI + AppKit
поверх аудиодвижка [BASS](https://www.un4seen.com/). Без иконки в Dock: окно открывается
по клику на иконку в меню-баре, а эфир продолжается после его закрытия.

[![CI](https://github.com/fso13/RadioApple/actions/workflows/ci.yml/badge.svg)](https://github.com/fso13/RadioApple/actions/workflows/ci.yml)
[![Security](https://github.com/fso13/RadioApple/actions/workflows/security.yml/badge.svg)](https://github.com/fso13/RadioApple/actions/workflows/security.yml)

![Главный экран RadioMac](https://raw.githubusercontent.com/fso13/RadioApple/main/site/assets/screenshots/main-light.jpg)

## Скачать

- [Последний релиз](https://github.com/fso13/RadioApple/releases/latest) — DMG, PKG,
  контрольные суммы и SBOM.
- [Сайт проекта](https://fso13.github.io/RadioApple/) — обзор и скриншоты.
- Требования: macOS 14 (Sonoma) или новее, Apple Silicon или Intel.

## Быстрый старт

1. Скачайте DMG из [релиза](https://github.com/fso13/RadioApple/releases/latest).
2. Откройте образ и перетащите **RadioMac** в «Программы».
3. Запустите приложение: иконка появится в меню-баре, окно — по левому клику.
4. Выберите станцию и нажмите Play. Подробнее — в разделе [Установка](Install).

## Что умеет

- **47 станций** в каталоге, свои станции, избранное и поиск.
- **Метаданные трека**: ICY, Icecast, SomaFM, Radio Paradise; обложки из iTunes;
  Now Playing в Control Center.
- **10-полосный эквалайзер** с пресетами и своей кривой.
- **Группы станций** и собственный порядок перетаскиванием.
- **Будильник-радио** с расписанием по дням недели и плавным нарастанием.
- **Локальная диагностика** с opt-in журналом и обнаружением аварийных завершений.
- **Диагностика потока**: кодек, битрейт, частота, каналы, буфер и сервер.
- **Светлая и тёмная темы** — одна монохромная система в двух инверсиях.
- **Живёт в меню-баре**: без Dock, с автозапуском и продолжением последней станции.
- **Нативная песочница**, без аккаунтов и телеметрии.

## Документация

| Раздел | О чём |
| --- | --- |
| [Установка](Install) | DMG, PKG, Gatekeeper, обновление и удаление |
| [Возможности](Features) | Интерфейс, воспроизведение, темы, меню-бар |
| [Горячие клавиши](Shortcuts) | Управление с клавиатуры и из меню |
| [Свои станции](Stations) | Добавление, ссылки на потоки, логотипы, данные |
| [Метаданные и обложки](Metadata) | Откуда берутся трек, исполнитель и картинка |
| [Эквалайзер](Equalizer) | Полосы, пресеты и известное ограничение BASS_FX |
| [Настройки](Settings) | Оформление, поведение, библиотека |
| [Архитектура](Architecture) | Как устроено приложение внутри |
| [Сборка](Build) | Xcode, тесты, установщики, подпись |
| [CI/CD и релизы](CICD) | GitHub Actions, релизы, GitHub Pages |
| [Безопасность](Security) | Песочница, SBOM, CVE-проверки, подпись |
| [Разработка и отладка](Development) | Debug-снимки, логи, стиль кода |
| [Решение проблем](Troubleshooting) | Если что-то не играет или не открывается |

## Для разработчиков

- Исходники: [github.com/fso13/RadioApple](https://github.com/fso13/RadioApple).
- Flutter-версия сохранена в `lib/` и `macos/` для сравнения; актуальная — нативная.
- Язык Swift 5, цель macOS 14, универсальная сборка (arm64 + x86_64).
- Лицензия BASS и аддонов — в `ThirdParty/BASS/bass.txt`.

---

Дизайн вдохновлён шотом [Office Radio app](https://dribbble.com/shots/19641552-Office-Radio-app)
(Marko Kolić / PROTOTYP). Реализация, графика и иконки — собственные.
