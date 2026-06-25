#!/usr/bin/env bash
# Extract the top-most version section from a release-please CHANGELOG and
# sanitize it to store-safe plain text (no markdown), capped at 4000 chars.
#
# Usage: release_notes.sh [path-to-CHANGELOG.md]   (default: CHANGELOG.md)
set -euo pipefail

CHANGELOG="${1:-CHANGELOG.md}"
MAX_LEN=4000

if [ ! -f "$CHANGELOG" ]; then
  echo "::error::release_notes.sh: changelog not found: $CHANGELOG" >&2
  exit 1
fi

# 1. Extract the block from the first version header (## [x.y.z] or ## x.y.z)
#    up to (but not including) the next ## header.
section="$(awk '
  /^## / {
    if (seen) exit          # second version header -> stop
    seen = 1
    next                    # drop the version header line itself
  }
  seen { print }
' "$CHANGELOG")"

if [ -z "$(printf "%s" "$section" | tr -d '[:space:]')" ]; then
  echo "::error::release_notes.sh: no version section found in $CHANGELOG" >&2
  exit 1
fi

# 2. Sanitize markdown -> plain text.
notes="$(printf "%s\n" "$section" \
  | sed -E 's/^#{1,6}[[:space:]]*//' \
  | sed -E 's/\[([^]]+)\]\([^)]*\)/\1/g' \
  | sed -E 's/`([^`]*)`/\1/g' \
  | sed -E 's/\*\*([^*]*)\*\*/\1/g' \
  | sed -E 's/^[[:space:]]*[\*\-][[:space:]]+/- /' \
  | sed -E 's/\*//g' \
  | sed -E '/^[[:space:]]*$/d')"

# 3. Cap length at a word boundary.
if [ "${#notes}" -gt "$MAX_LEN" ]; then
  notes="$(printf "%s" "$notes" | cut -c1-$((MAX_LEN-1)))…"
fi

printf "%s\n" "$notes"
