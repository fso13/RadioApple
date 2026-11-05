#!/usr/bin/env bash
#
# Builds RadioiOS and installs it on the connected iPhone.
#
# The App Store is not involved: the app is signed with a development profile
# from your Apple ID (a free "Personal Team" is enough) and copied to the phone
# with devicectl. A free profile expires after 7 days; run this script again to
# renew it. Library and settings on the phone are preserved.
#
# Usage:
#   scripts/install_ios.sh
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/install_ios.sh
#   RADIOIOS_BUNDLE_ID=com.example.radiomac scripts/install_ios.sh
#   IPHONE_UDID=00008110-... scripts/install_ios.sh
#
# Before the first run, sign in to your Apple ID in Xcode → Settings → Accounts
# and, if Xcode asks, select the team for the RadioiOS target once.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="${RADIOIOS_BUNDLE_ID:-com.fso13.radioMac.ios}"
TEAM="${DEVELOPMENT_TEAM:-}"

if [[ -z "$TEAM" ]]; then
  TEAM="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamManagerLastSelectedTeamID 2>/dev/null || true)"
fi

# Find the first paired iPhone unless the UDID was provided explicitly.
UDID="${IPHONE_UDID:-}"
if [[ -z "$UDID" ]]; then
  TMP_JSON="$(mktemp -t radioios-devices)"
  trap 'rm -f "$TMP_JSON"' EXIT
  xcrun devicectl list devices --json-output "$TMP_JSON" >/dev/null 2>&1 || true
  UDID="$(python3 - "$TMP_JSON" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, ValueError):
    sys.exit(0)

for device in payload.get("result", {}).get("devices", []):
    hardware = device.get("properties", {}).get("hardware", {})
    if hardware.get("deviceType") != "iPhone":
        continue
    connection = device.get("properties", {}).get("connection", {})
    if connection.get("pairingState") != "paired":
        continue
    udid = hardware.get("udid") or device.get("hardwareProperties", {}).get("udid")
    if udid:
        print(udid)
        break
PY
)"
fi

if [[ -z "$UDID" ]]; then
  echo "Не найден подключённый iPhone." >&2
  echo "Подключите телефон кабелем, разблокируйте и разрешите доступ к компьютеру." >&2
  echo "Список устройств: xcrun devicectl list devices" >&2
  exit 1
fi

if [[ -z "$TEAM" ]]; then
  echo "Не найдена команда разработчика." >&2
  echo "Укажите её явно: DEVELOPMENT_TEAM=XXXXXXXXXX scripts/install_ios.sh" >&2
  exit 1
fi

echo "iPhone:    $UDID"
echo "Bundle ID: $BUNDLE_ID"
echo "Team:      $TEAM"

BUILD_DIR=".build/IOSDevice"
APP="$BUILD_DIR/Build/Products/Debug-iphoneos/RadioiOS.app"
LOG="$BUILD_DIR/build.log"
mkdir -p "$BUILD_DIR"

set +e
xcodebuild \
  -project RadioMac.xcodeproj \
  -scheme RadioiOS \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build >"$LOG" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "Сборка с подписью не удалась. Последние строки лога:" >&2
  tail -n 25 "$LOG" >&2
  cat >&2 <<'HINT'

Что проверить:
  1. Xcode → Settings → Accounts: Apple ID должен быть активен.
     Если Xcode просит пароль — войдите заново (это интерактивный шаг).
  2. Xcode → проект → target RadioiOS → Signing & Capabilities:
     выберите свою команду (Personal Team подходит).
  3. Если Bundle ID занят — задайте другой:
     RADIOIOS_BUNDLE_ID=com.<фамилия>.radiomac scripts/install_ios.sh
HINT
  exit $STATUS
fi

if [[ ! -d "$APP" ]]; then
  echo "Приложение не найдено: $APP" >&2
  exit 1
fi

echo "Устанавливаю на iPhone…"
xcrun devicectl device install app --device "$UDID" "$APP"

echo "Запускаю…"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" || {
  echo "Установка прошла, но автозапуск не удался. Откройте RadioMac на телефоне вручную." >&2
}

echo
echo "Готово. Бесплатный профиль действует 7 дней: запустите скрипт ещё раз перед истечением,"
echo "чтобы продлить подпись. Библиотека и настройки сохраняются."
