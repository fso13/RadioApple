#!/usr/bin/env bash
#
# Double-click launcher: builds RadioMac and installs it into /Applications.
#
# Finder runs this file in Terminal. All the work happens in scripts/install.sh;
# this wrapper only asks for confirmation and reports the result.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="RadioMac"
LOG="$ROOT/.build/install-launcher.log"

# ---------------------------------------------------------------- GUI helpers
ICON_PATH="$ROOT/installer/RadioMac.icns"

dialog_ok() {
    if command -v osascript >/dev/null 2>&1; then
        if osascript - "$1" "$ICON_PATH" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
    set messageText to item 1 of argv
    set iconPath to item 2 of argv
    try
        set dialogIcon to (POSIX file iconPath) as alias
        display dialog messageText buttons {"OK"} default button 1 with title "RadioMac" with icon dialogIcon
    on error
        display dialog messageText buttons {"OK"} default button 1 with title "RadioMac" with icon note
    end try
end run
APPLESCRIPT
        then
            return 0
        fi
    fi
    printf '\n%s\n' "$1"
}

confirm_install() {
    local message="$1"
    local answer

    if command -v osascript >/dev/null 2>&1; then
        answer="$(osascript - "$message" "$ICON_PATH" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set messageText to item 1 of argv
    set iconPath to item 2 of argv
    try
        set dialogIcon to (POSIX file iconPath) as alias
        display dialog messageText buttons {"Отмена", "Установить"} default button "Установить" with title "RadioMac" with icon dialogIcon
    on error
        display dialog messageText buttons {"Отмена", "Установить"} default button "Установить" with title "RadioMac" with icon note
    end try
    return button returned of result
end run
APPLESCRIPT
        )"
        if [[ "$answer" == "Установить" ]]; then
            return 0
        fi
        # Cancel or a broken AppleScript session both mean "do nothing".
        return 1
    fi

    printf '%s [y/N] ' "$message"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# --------------------------------------------------------------------- install
main() {
    local message
    message="Установить RadioMac в /Applications?

Приложение живёт в меню-баре, не появляется в Dock и продолжает играть после закрытия окна.
Сборка Release займёт около минуты; для записи в /Applications может потребоваться пароль администратора."

    confirm_install "$message" || exit 0

    mkdir -p "$ROOT/.build"
    printf 'Installing %s…\n' "$APP_NAME"

    if "$ROOT/scripts/install.sh" >"$LOG" 2>&1; then
        dialog_ok "RadioMac установлен в /Applications и запущен.

Иконка — в меню-баре: левый клик открывает окно, правый — меню с настройками и выходом."
    else
        printf 'Install failed, see %s\n' "$LOG" >&2
        dialog_ok "Не удалось установить RadioMac.

Лог: $LOG"
        exit 1
    fi
}

main "$@"
