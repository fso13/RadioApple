#!/usr/bin/env bash
#
# Build a distributable installer for RadioMac:
#   dist/RadioMac-<version>.dmg   drag-and-drop disk image
#   dist/RadioMac-<version>.pkg   double-click installer
#   dist/SHA256SUMS.txt           checksums
#
# Usage:
#   scripts/make_installer.sh [--version 1.2.3]
#                             [--identity "Developer ID Application: Name (TEAM)"]
#                             [--installer-identity "Developer ID Installer: Name (TEAM)"]
#                             [--skip-build] [--skip-verify]
#
# Without --identity the app keeps its ad-hoc signature, which is fine for local
# use but will be blocked by Gatekeeper on other Macs (see README).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/RadioMac.xcodeproj"
SCHEME="RadioMac"
APP_NAME="RadioMac"
BUNDLE_ID="com.fso13.radioMac"
DD="$ROOT/.build/DerivedData"
APP="$DD/Build/Products/Release/$APP_NAME.app"
DIST="$ROOT/dist"
STAGE="$ROOT/.build/installer"
ENTITLEMENTS="$ROOT/RadioMac/Resources/RadioMac.entitlements"
ICON_SOURCE="$ROOT/RadioMac/Resources/Assets.xcassets/AppIcon.appiconset"

VERSION=""
IDENTITY="${CODESIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${CODESIGN_INSTALLER_IDENTITY:-}"
SKIP_BUILD=0
SKIP_VERIFY=0
VOLUME_NAME=""
DMG_PATH=""
PKG_PATH=""

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?missing value for --version}"; shift 2 ;;
        --identity) IDENTITY="${2:?missing value for --identity}"; shift 2 ;;
        --installer-identity) INSTALLER_IDENTITY="${2:?missing value}"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --skip-verify) SKIP_VERIFY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "macOS is required"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found — install Xcode"
command -v pkgbuild >/dev/null 2>&1 || die "pkgbuild not found — install Xcode command line tools"

if [[ $SKIP_VERIFY -eq 0 ]]; then
    info "Verifying vendored BASS binaries"
    "$ROOT/scripts/verify_third_party.sh" || die "third-party files failed verification"
fi

# Prefer the macOS 26+ image tool, fall back to hdiutil on older systems.
DISKUTIL_IMAGE=0
if diskutil image create from --help >/dev/null 2>&1; then
    DISKUTIL_IMAGE=1
fi

create_image() { # <source folder or dmg> <destination> <format> <volumeName>
    local source="$1" destination="$2" format="$3" name="$4"
    rm -f "$destination"
    if [[ $DISKUTIL_IMAGE -eq 1 ]]; then
        diskutil image create from --format "$format" --volumeName "$name" "$source" "$destination"
    else
        hdiutil create -quiet -ov -volname "$name" -fs HFS+ -srcfolder "$source" -format "$format" "$destination"
    fi
}

attach_image() { # <image> <mountpoint>
    if [[ $DISKUTIL_IMAGE -eq 1 ]]; then
        diskutil image attach --mountOptions nobrowse --mountPoint "$2" "$1" >/dev/null
    else
        hdiutil attach -quiet -nobrowse -readwrite -mountpoint "$2" "$1" >/dev/null
    fi
}

detach_image() { # <mountpoint>
    if [[ $DISKUTIL_IMAGE -eq 1 ]]; then
        diskutil eject "$1" >/dev/null 2>&1 || true
    else
        hdiutil detach -quiet "$1" >/dev/null 2>&1 \
            || hdiutil detach -force -quiet "$1" >/dev/null 2>&1 || true
    fi
}

compress_image() { # <source image> <destination dmg>
    rm -f "$2"
    if [[ $DISKUTIL_IMAGE -eq 1 ]]; then
        diskutil image create from --format UDZO "$1" "$2" >/dev/null
    else
        hdiutil convert -quiet "$1" -format UDZO -o "${2%.dmg}"
    fi
}

BUILD_SETTINGS=()
if [[ -n "$VERSION" ]]; then
    # Ship the requested version inside the bundle, not just in the file names.
    BUILD_SETTINGS+=("MARKETING_VERSION=$VERSION")
fi

mkdir -p "$ROOT/.build"
: > "$ROOT/.build/installer-build.log"

if [[ $SKIP_BUILD -eq 0 ]]; then
    info "Building $APP_NAME (Release, universal)"
    if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -derivedDataPath "$DD" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
        "${BUILD_SETTINGS[@]}" build \
        > "$ROOT/.build/installer-build.log" 2>&1; then
        tail -n 40 "$ROOT/.build/installer-build.log" >&2
        die "build failed (full log: .build/installer-build.log)"
    fi
else
    info "Skipping build (--skip-build)"
fi

[[ -d "$APP" ]] || die "app not found at $APP — build it first"
[[ -f "$ENTITLEMENTS" ]] || die "entitlements not found at $ENTITLEMENTS"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
if [[ -n "$VERSION" && "$VERSION" != "$APP_VERSION" ]]; then
    die "--version $VERSION does not match the built app ($APP_VERSION); rebuild without --skip-build or omit --version"
fi
VERSION="$APP_VERSION"

info "Version $VERSION (build $BUILD_NUMBER)"

# ------------------------------------------------------------------ signature
if [[ -n "$IDENTITY" ]]; then
    info "Signing with: $IDENTITY"
    while IFS= read -r -d '' dylib; do
        /usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$dylib"
    done < <(find "$APP/Contents/Frameworks" -name '*.dylib' -print0 2>/dev/null)
    /usr/bin/codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
    /usr/bin/codesign --verify --deep --strict "$APP"
else
    warn "keeping the ad-hoc signature (set CODESIGN_IDENTITY to sign for distribution)"
fi

# --------------------------------------------------------------------- staging
info "Staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/dmg" "$STAGE/pkg-root" "$DIST"

ditto "$APP" "$STAGE/dmg/$APP_NAME.app"
ln -s /Applications "$STAGE/dmg/Applications"
ditto "$APP" "$STAGE/pkg-root/$APP_NAME.app"

# Volume icon (best effort).
HAVE_ICON=0
ICNS="$STAGE/$APP_NAME.icns"
if [[ -d "$ICON_SOURCE" ]] && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$STAGE/icon.iconset"
    mkdir -p "$ICONSET"
    cp "$ICON_SOURCE/app_icon_16.png"   "$ICONSET/icon_16x16.png"
    cp "$ICON_SOURCE/app_icon_32.png"   "$ICONSET/icon_16x16@2x.png"
    cp "$ICON_SOURCE/app_icon_32.png"   "$ICONSET/icon_32x32.png"
    cp "$ICON_SOURCE/app_icon_64.png"   "$ICONSET/icon_32x32@2x.png"
    cp "$ICON_SOURCE/app_icon_128.png"  "$ICONSET/icon_128x128.png"
    cp "$ICON_SOURCE/app_icon_256.png"  "$ICONSET/icon_128x128@2x.png"
    cp "$ICON_SOURCE/app_icon_256.png"  "$ICONSET/icon_256x256.png"
    cp "$ICON_SOURCE/app_icon_512.png"  "$ICONSET/icon_256x256@2x.png"
    cp "$ICON_SOURCE/app_icon_512.png"  "$ICONSET/icon_512x512.png"
    cp "$ICON_SOURCE/app_icon_1024.png" "$ICONSET/icon_512x512@2x.png"
    if iconutil -c icns "$ICONSET" -o "$ICNS" 2>/dev/null; then
        HAVE_ICON=1
    fi
fi

# ------------------------------------------------------------------------- dmg
VOLUME_NAME="$APP_NAME $VERSION"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
info "Creating $APP_NAME-$VERSION.dmg (drag & drop window)"

# Prefer dmgbuild: it writes the Finder layout (.DS_Store) itself and needs no
# automation permissions. It is provisioned into a local venv on first use.
# Long, non-ASCII paths break the venv script's shebang, so always call the
# module through the interpreter.
DMGBUILD_CMD=()
VENV="$ROOT/.build/tools/dmgbuild-venv"
VENV_PY="$VENV/bin/python"
REQUIREMENTS="$ROOT/scripts/requirements-installer.txt"
if command -v dmgbuild >/dev/null 2>&1; then
    DMGBUILD_CMD=(dmgbuild)
elif [[ -x "$VENV_PY" ]] && "$VENV_PY" -c 'import dmgbuild' >/dev/null 2>&1; then
    DMGBUILD_CMD=("$VENV_PY" -m dmgbuild)
elif command -v python3 >/dev/null 2>&1; then
    info "Provisioning installer tooling into .build/tools/dmgbuild-venv"
    if python3 -m venv "$VENV" >/dev/null 2>&1 \
        && "$VENV/bin/pip" install --quiet --disable-pip-version-check \
            -r "$REQUIREMENTS" >/dev/null 2>&1 \
        && "$VENV_PY" -c 'import dmgbuild' >/dev/null 2>&1; then
        DMGBUILD_CMD=("$VENV_PY" -m dmgbuild)
    fi
fi

STYLED_DMG=0
if [[ ${#DMGBUILD_CMD[@]} -gt 0 && -f "$ROOT/installer/background.png" && -f "$ICNS" ]]; then
    rm -f "$DMG_PATH"
    if "${DMGBUILD_CMD[@]}" -s "$ROOT/scripts/dmg_settings.py" \
        -D "app=$STAGE/dmg/$APP_NAME.app" \
        -D "background=$ROOT/installer/background.png" \
        -D "volume_icon=$ICNS" \
        "$VOLUME_NAME" "$DMG_PATH" >> "$ROOT/.build/installer-build.log" 2>&1; then
        STYLED_DMG=1
    else
        warn "dmgbuild failed, falling back to a plain image (.build/installer-build.log)"
    fi
fi

if [[ $STYLED_DMG -eq 0 ]]; then
    CHROME_OK=0
    if [[ $HAVE_ICON -eq 1 ]] && command -v SetFile >/dev/null 2>&1; then
        RW_IMAGE="$STAGE/$APP_NAME-rw.dmg"
        MNT="$STAGE/mnt"
        mkdir -p "$MNT"
        # A writable intermediate image is only needed to attach the volume icon;
        # if any step fails the plain DMG below is used instead.
        if hdiutil create -quiet -ov -volname "$VOLUME_NAME" -fs HFS+ \
                -srcfolder "$STAGE/dmg" -format UDRW "$RW_IMAGE" 2>/dev/null \
            && attach_image "$RW_IMAGE" "$MNT"; then
            cp "$ICNS" "$MNT/.VolumeIcon.icns" 2>/dev/null || true
            SetFile -a C "$MNT" 2>/dev/null || true
            detach_image "$MNT"
            if compress_image "$RW_IMAGE" "$DMG_PATH"; then
                CHROME_OK=1
            fi
        else
            detach_image "$MNT"
        fi
    fi
    if [[ $CHROME_OK -eq 0 ]]; then
        create_image "$STAGE/dmg" "$DMG_PATH" UDZO "$VOLUME_NAME"
    fi
fi

[[ -f "$DMG_PATH" ]] || die "failed to create the disk image"

hdiutil verify "$DMG_PATH" >/dev/null 2>&1 || warn "hdiutil verify reported a problem"

# ------------------------------------------------------------------------- pkg
info "Creating $APP_NAME-$VERSION.pkg"
COMPONENT="$STAGE/component.pkg"
pkgbuild --quiet \
    --root "$STAGE/pkg-root" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location /Applications \
    "$COMPONENT"

RESOURCES="$STAGE/resources"
mkdir -p "$RESOURCES"
cat > "$RESOURCES/welcome.html" <<HTML
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,'Helvetica Neue',sans-serif;font-size:13px;line-height:1.5;color:#282a36">
<h2 style="margin:0 0 8px">RadioMac $VERSION</h2>
<p>Плеер интернет-радио для меню-бара macOS. Приложение не показывается в Dock и продолжает
играть после закрытия окна.</p>
<ul style="padding-left:18px">
  <li>Левый клик по иконке в меню-баре — показать или скрыть окно</li>
  <li>Правый клик — играть/пауза, стоп, настройки, выход</li>
  <li>⌘N — новая станция, ⌘F — поиск, пробел — пауза</li>
</ul>
<p>Станции, избранное, громкость и настройки эквалайзера сохраняются при обновлении.</p>
</body>
</html>
HTML

cat > "$RESOURCES/conclusion.html" <<HTML
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,'Helvetica Neue',sans-serif;font-size:13px;line-height:1.5;color:#282a36">
<h2 style="margin:0 0 8px">Готово</h2>
<p>RadioMac установлен в папку «Программы». Иконка приложения появится в меню-баре —
откройте окно кликом по ней.</p>
</body>
</html>
HTML

cat > "$STAGE/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>RadioMac</title>
    <organization>com.fso13</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.fso13.radioMac"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.fso13.radioMac" visible="false">
        <pkg-ref id="com.fso13.radioMac"/>
    </choice>
    <pkg-ref id="com.fso13.radioMac" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
XML

UNSIGNED_PKG="$STAGE/$APP_NAME-unsigned.pkg"
PKG_PATH="$DIST/$APP_NAME-$VERSION.pkg"
productbuild --quiet \
    --distribution "$STAGE/distribution.xml" \
    --resources "$RESOURCES" \
    --package-path "$STAGE" \
    "$UNSIGNED_PKG"

if [[ -n "$INSTALLER_IDENTITY" ]]; then
    info "Signing package with: $INSTALLER_IDENTITY"
    productsign --sign "$INSTALLER_IDENTITY" "$UNSIGNED_PKG" "$PKG_PATH"
else
    cp "$UNSIGNED_PKG" "$PKG_PATH"
fi

# -------------------------------------------------------------------- checksums
( cd "$DIST" && shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$PKG_PATH")" > SHA256SUMS.txt )

info "Done"
printf '   %s  (%s)\n' "$DMG_PATH" "$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
printf '   %s  (%s)\n' "$PKG_PATH" "$(du -h "$PKG_PATH" | cut -f1 | tr -d ' ')"
printf '   %s\n' "$DIST/SHA256SUMS.txt"
if [[ -z "$IDENTITY" ]]; then
    printf '\n   Ad-hoc signature: on other Macs run\n'
    printf '     xattr -dr com.apple.quarantine /Applications/RadioMac.app\n'
    printf '   or sign with CODESIGN_IDENTITY / CODESIGN_INSTALLER_IDENTITY.\n'
fi
