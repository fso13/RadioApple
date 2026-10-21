#!/usr/bin/env bash
#
# Build RadioMac (if needed) and install it into /Applications, then launch it.
#
# Usage:
#   scripts/install.sh [--skip-build] [--no-launch] [--target DIR]
#
# The app keeps its data because the bundle identifier (and therefore the sandbox
# container) stays the same as in the Flutter build.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RadioMac"
DD="$ROOT/.build/DerivedData"
BUILT_APP="$DD/Build/Products/Release/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
TARGET="$INSTALL_DIR/$APP_NAME.app"
SKIP_BUILD=0
LAUNCH=1

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1; shift ;;
        --no-launch) LAUNCH=0; shift ;;
        --target) INSTALL_DIR="${2:?missing value for --target}"; shift 2 ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

TARGET="$INSTALL_DIR/$APP_NAME.app"

# Create the destination when it does not exist yet (e.g. a custom target dir).
if [[ ! -d "$INSTALL_DIR" ]]; then
    mkdir -p "$INSTALL_DIR" 2>/dev/null || true
fi
[[ -d "$INSTALL_DIR" ]] || die "cannot create $INSTALL_DIR"

if [[ $SKIP_BUILD -eq 0 ]]; then
    info "Building $APP_NAME (Release)"
    mkdir -p "$ROOT/.build"
    if ! xcodebuild -project "$ROOT/RadioMac.xcodeproj" -scheme "$APP_NAME" \
        -configuration Release -derivedDataPath "$DD" build \
        > "$ROOT/.build/install-build.log" 2>&1; then
        tail -n 40 "$ROOT/.build/install-build.log" >&2
        die "build failed (full log: .build/install-build.log)"
    fi
fi

[[ -d "$BUILT_APP" ]] || die "app not found at $BUILT_APP — run without --skip-build"

# Stop a running copy so the bundle can be replaced cleanly.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    info "Stopping the running copy"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

SUDO=""
if [[ ! -w "$INSTALL_DIR" ]]; then
    command -v sudo >/dev/null 2>&1 || die "$INSTALL_DIR is not writable and sudo is unavailable"
    SUDO="sudo"
fi

info "Installing into $TARGET"
$SUDO rm -rf "$TARGET"
$SUDO ditto "$BUILT_APP" "$TARGET"
$SUDO xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

# A sandboxed app must keep the entitlements of the built product; verify the copy
# is still valid before launching it.
/usr/bin/codesign --verify --strict "$TARGET" 2>/dev/null || printf ' warning: codesign verification failed for %s\n' "$TARGET"

if [[ $LAUNCH -eq 1 ]]; then
    info "Launching"
    open "$TARGET"
fi

info "Installed: $TARGET"
