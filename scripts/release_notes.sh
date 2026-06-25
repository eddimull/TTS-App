#!/usr/bin/env bash
# Extract the top-most version section from a release-please CHANGELOG and
# sanitize it to store-safe plain text (no markdown), capped at a max length.
#
# Usage: release_notes.sh [path-to-CHANGELOG.md] [max-chars]
#   path-to-CHANGELOG.md  default: CHANGELOG.md
#   max-chars             default: 4000 (Apple's "What to Test"/review limit).
#                         Pass 500 for Google Play's "What's new" per-language
#                         limit, which is much smaller than Apple's.
set -euo pipefail

CHANGELOG="${1:-CHANGELOG.md}"
MAX_LEN="${2:-4000}"

# max-chars must be an integer >= 2 (we slice MAX_LEN-1 chars + a 1-char
# ellipsis); otherwise the arithmetic below fails with an opaque shell error.
if ! printf '%s' "$MAX_LEN" | grep -Eq '^[0-9]+$' || [ "$MAX_LEN" -lt 2 ]; then
  echo "::error::release_notes.sh: max-chars must be an integer >= 2 (got: $MAX_LEN)" >&2
  exit 1
fi

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
  | sed -E 's/^[[:space:]]*[*-][[:space:]]+/- /' \
  | sed -E 's/\*//g' \
  | sed -E '/^[[:space:]]*$/d')"

# 3. Hard-cap total length (leaving room for the 1-char ellipsis).
if [ "${#notes}" -gt "$MAX_LEN" ]; then
  notes="${notes:0:$((MAX_LEN-1))}…"
fi

printf "%s\n" "$notes"
