#!/usr/bin/env bash
#
# Verifies the vendored BASS binaries against ThirdParty/BASS/SHA256SUMS.
# Run with --update after intentionally replacing a vendor file.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/ThirdParty/BASS"
MANIFEST="$DIR/SHA256SUMS"

[[ -d "$DIR" ]] || { echo "error: $DIR not found" >&2; exit 1; }

if [[ "${1:-}" == "--update" ]]; then
    ( cd "$DIR" && shasum -a 256 ./*.h ./*.dylib > SHA256SUMS )
    echo "updated $MANIFEST"
    exit 0
fi

[[ -f "$MANIFEST" ]] || { echo "error: $MANIFEST not found" >&2; exit 1; }

cd "$DIR"
if ! shasum -a 256 -c SHA256SUMS; then
    echo >&2
    echo "Vendored BASS files do not match the manifest." >&2
    echo "If the update is intentional, run: scripts/verify_third_party.sh --update" >&2
    exit 1
fi
echo "third-party binaries: OK"
