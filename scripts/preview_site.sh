#!/usr/bin/env bash
#
# Serves the static site locally: http://127.0.0.1:8000
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8000}"

"$ROOT/scripts/check_site.py"
echo "RadioMac site → http://127.0.0.1:${PORT}/"
exec python3 -m http.server "$PORT" --directory "$ROOT/site"
