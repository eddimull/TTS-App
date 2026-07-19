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
# Emoji are stripped so a rude/unintended emoji can't reach the store notes,
# but the surrounding feature text is preserved with clean spacing:
assert_not_contains "$OUT" "🖕" "middle-finger emoji stripped"
assert_not_contains "$OUT" "🎉" "celebration emoji stripped"
assert_contains "$OUT" "add to the quick-reaction set" "emoji removed without eating surrounding words"
assert_not_contains "$OUT" "add  to" "no double space left where emoji was"
# BMP emoji (outside the U+1Fxxx planes) and skin-tone modifiers must also go —
# a block-range approach would miss ⏰ (U+23F0) and leave a stray 🏻 (U+1F3FB).
assert_not_contains "$OUT" "⏰" "BMP emoji (alarm clock) stripped"
assert_not_contains "$OUT" "👍" "thumbs-up emoji stripped"
assert_not_contains "$OUT" "🏻" "skin-tone modifier stripped (no orphan)"
assert_contains "$OUT" "reminder alerts for upcoming rehearsals" "BMP+skin-tone removed without eating words"
# Under Apple's 4000-char cap:
assert_max_len "$OUT" 4000 "within Apple limit"

# Truncation: a long changelog must be capped at 4000 chars.
LONG_CL="$(mktemp)"
{
  echo "## [9.9.9](url) (2026-01-01)"
  echo
  echo "### Features"
  echo
  i=0; while [ "$i" -lt 400 ]; do
    echo "* feat: a reasonably long feature description line number $i to add bulk ([#$i](https://example.com/issues/$i))"
    i=$((i+1))
  done
} > "$LONG_CL"
LONG_OUT="$(bash "$SCRIPT" "$LONG_CL")"
rm -f "$LONG_CL"
assert_max_len "$LONG_OUT" 4000 "long changelog capped at 4000"
case "$LONG_OUT" in
  *"…") ;;
  *) echo "FAIL: long changelog should end with ellipsis"; fails=$((fails+1)) ;;
esac

# Custom max-chars arg: Google Play's whatsnew uses a 500-char cap.
LONG_CL_500="$(mktemp)"
{
  echo "## [9.9.9](url) (2026-01-01)"
  echo
  echo "### Features"
  echo
  i=0; while [ "$i" -lt 400 ]; do
    echo "* feat: a reasonably long feature description line number $i to add bulk ([#$i](https://example.com/issues/$i))"
    i=$((i+1))
  done
} > "$LONG_CL_500"
OUT_500="$(bash "$SCRIPT" "$LONG_CL_500" 500)"
rm -f "$LONG_CL_500"
assert_max_len "$OUT_500" 500 "custom 500-char cap honored"
case "$OUT_500" in
  *"…") ;;
  *) echo "FAIL: 500-capped output should end with ellipsis"; fails=$((fails+1)) ;;
esac

# Invalid max-chars args must fail cleanly with a non-zero exit, not an
# opaque arithmetic error.
for bad in foo 0 1 -5 3.5; do
  if bash "$SCRIPT" "$FIXTURE" "$bad" >/dev/null 2>&1; then
    echo "FAIL: max-chars '$bad' should have been rejected"; fails=$((fails+1))
  fi
done

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; exit 1; fi
