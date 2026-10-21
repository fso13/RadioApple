#!/usr/bin/env bash
#
# Publishes the wiki/ sources to https://github.com/fso13/RadioApple/wiki.
# GitHub creates the wiki git repository only after the first page exists in the
# web UI, so run this once after creating any page at /wiki.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIKI_URL="${WIKI_URL:-https://github.com/fso13/RadioApple.wiki.git}"
WORK="$ROOT/.build/wiki-repo"
MESSAGE="docs: sync wiki"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --message) MESSAGE="${2:?--message requires a value}"; shift 2 ;;
        -h|--help)
            echo "usage: scripts/publish_wiki.sh [--dry-run] [--message TEXT]"
            exit 0
            ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

"$ROOT/scripts/check_wiki.py"

if ! GIT_TERMINAL_PROMPT=0 git ls-remote "$WIKI_URL" >/dev/null 2>&1; then
    cat <<EOF
Wiki is not initialized yet (or credentials are unavailable).

GitHub creates the wiki git repository only after the first page exists in the UI:
  1. Open https://github.com/fso13/RadioApple/wiki
  2. Click "Create the first page", enter "Home" and save.
  3. Run this script again.

If the wiki already exists, check your GitHub access/credentials for:
  $WIKI_URL
EOF
    exit 1
fi

rm -rf "$WORK"
GIT_TERMINAL_PROMPT=0 git clone "$WIKI_URL" "$WORK"
rsync -a --delete --exclude .git "$ROOT/wiki/" "$WORK/"

cd "$WORK"
git add -A
if git diff --cached --quiet; then
    echo "wiki is already up to date"
    exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "dry run: changes that would be published"
    git status --short
    exit 0
fi

if git config user.email >/dev/null 2>&1; then
    git commit -m "$MESSAGE"
else
    git -c user.name="RadioMac Wiki" \
        -c user.email="wiki@users.noreply.github.com" \
        commit -m "$MESSAGE"
fi

if ! GIT_TERMINAL_PROMPT=0 git push origin HEAD; then
    echo >&2
    echo "Push failed. Check GitHub credentials (Keychain or SSH) and try again." >&2
    exit 1
fi

echo "published: https://github.com/fso13/RadioApple/wiki"
