#!/usr/bin/env bash
# Self-contained assertions for scripts/release_notes.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SCRIPT=scripts/release_notes.sh
FIXTURE=test/fixtures/CHANGELOG.sample.md
fails=0

assert_contains() { # haystack needle label
  case "$1" in
    *"$2"*) ;;
    *) echo "FAIL: $3 — expected to contain: $2"; fails=$((fails+1)) ;;
  esac
}
assert_not_contains() {
  case "$1" in
    *"$2"*) echo "FAIL: $3 — expected NOT to contain: $2"; fails=$((fails+1)) ;;
    *) ;;
  esac
}
assert_max_len() { # text max label
  local len=${#1}
  if [ "$len" -gt "$2" ]; then echo "FAIL: $3 — length $len > $2"; fails=$((fails+1)); fi
}

OUT="$(bash "$SCRIPT" "$FIXTURE")"

# Only the top (1.3.0) section is extracted, sanitized to plain text.
assert_contains "$OUT" "add media upload to event detail" "includes top feature"
assert_contains "$OUT" "payout config create" "includes second feature"
assert_contains "$OUT" "iOS build failing" "includes bug fix"
assert_not_contains "$OUT" "older feature that must NOT appear" "excludes prior version"
# Markdown stripped (no syntax), but link *text* is preserved as plain text:
assert_not_contains "$OUT" "**" "no bold markers"
assert_not_contains "$OUT" "](http" "no markdown link syntax"
assert_not_contains "$OUT" "[" "no leftover link brackets"
assert_contains "$OUT" "#48" "issue ref kept as plain text"
# Under Apple's 4000-char cap:
assert_max_len "$OUT" 4000 "within Apple limit"

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; exit 1; fi
