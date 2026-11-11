#!/usr/bin/env bash
# Post a drafted issue or comment with gh.  Usage: ./submit.sh <draft.md> [--dry-run]
# Header keys (in the leading <!-- --> block): repo, and either title (new issue)
# or issue + kind: comment (comment on an existing issue).
set -euo pipefail
f=$1
key() { sed -n "1,/^-->\$/s/^$1: //p" "$f" | head -1; }
repo=$(key repo); title=$(key title); issue=$(key issue); kind=$(key kind)
body=$(sed '1,/^-->$/d' "$f")
if [ "${2:-}" = "--dry-run" ]; then
  if [ "$kind" = comment ]; then echo "comment on $repo#$issue"; else echo "new issue in $repo: $title"; fi
  printf -- '---\n%s\n' "$body" | head -25; echo "... ($(printf '%s' "$body" | wc -c) bytes)"; exit 0
fi
if [ "$kind" = comment ]; then gh issue comment "$issue" -R "$repo" --body "$body"
else gh issue create -R "$repo" --title "$title" --body "$body"; fi
