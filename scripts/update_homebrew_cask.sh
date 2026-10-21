#!/usr/bin/env bash
# Render the RadioMac cask and push it to fso13/homebrew-tap.
#
# Usage: scripts/update_homebrew_cask.sh <version> <sha256> <tap-token>
# The token needs contents:write on fso13/homebrew-tap.
set -euo pipefail

VERSION="${1:-}"
SHA256="${2:-}"
TOKEN="${3:-${HOMEBREW_TAP_TOKEN:-}}"
TAP_REPO="${HOMEBREW_TAP_REPO:-fso13/homebrew-tap}"

if [[ -z "$VERSION" || -z "$SHA256" || -z "$TOKEN" ]]; then
  echo "usage: $0 <version> <sha256> <tap-token>" >&2
  exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "unsupported version: $VERSION" >&2
  exit 2
fi
if [[ ! "$SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "invalid sha256: $SHA256" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/packaging/homebrew/radiomac.rb.template"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "missing template: $TEMPLATE" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/radiomac-tap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --depth 1 \
  "https://x-access-token:${TOKEN}@github.com/${TAP_REPO}.git" "$WORK/tap"
mkdir -p "$WORK/tap/Casks"

sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__SHA256__/${SHA256}/g" \
    "$TEMPLATE" > "$WORK/tap/Casks/radiomac.rb"

cd "$WORK/tap"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if [[ -z "$(git status --porcelain -- Casks/radiomac.rb)" ]]; then
  echo "Cask is already at ${VERSION}."
  exit 0
fi

git add Casks/radiomac.rb
git commit --quiet -m "radiomac ${VERSION}" -m "Refs fso13/RadioApple#9"
git push --quiet
echo "Updated ${TAP_REPO} to radiomac ${VERSION}."
