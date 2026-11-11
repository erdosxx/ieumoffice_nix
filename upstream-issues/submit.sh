#!/usr/bin/env bash
# Submit a drafted issue to GitHub with gh.  Usage: ./submit.sh 01-*.md [--dry-run]
set -euo pipefail
f=$1
repo=$(sed -n 's/^repo: //p' "$f" | head -1)
title=$(sed -n 's/^title: //p' "$f" | head -1)
body=$(sed '1,/^-->$/d' "$f")
if [ "${2:-}" = "--dry-run" ]; then printf 'repo:  %s\ntitle: %s\n---\n%s\n' "$repo" "$title" "$body" | head -20; exit 0; fi
gh issue create -R "$repo" --title "$title" --body "$body"
