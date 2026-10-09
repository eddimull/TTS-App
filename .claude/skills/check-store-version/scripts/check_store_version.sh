#!/usr/bin/env bash
# Is the version in pubspec.yaml still uploadable to App Store Connect?
#
# Apple rejects any upload whose CFBundleShortVersionString is not higher
# than the version already approved — and the iOS Build workflow uploads
# every push to main labelled with the pubspec version. This prints the
# pubspec version, the latest GitHub release, the version live on the App
# Store, the last iOS Build result, and a verdict.
#
# Usage: check_store_version.sh   (run from anywhere inside the repo)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

BUNDLE_ID="band.tts.mate"
WORKFLOW="ios.yml"

pubspec_full="$(sed -n 's/^version: *//p' pubspec.yaml | head -1)"
pubspec_ver="${pubspec_full%%+*}"
pubspec_build="${pubspec_full#*+}"

latest_tag="$(gh release list --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"

lookup="$(curl -fsS --max-time 15 "https://itunes.apple.com/lookup?bundleId=${BUNDLE_ID}" 2>/dev/null || true)"
store_ver="$(printf '%s' "$lookup" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); r=d["results"][0]; print(r["version"], r["currentVersionReleaseDate"])
except Exception: print("")' 2>/dev/null || true)"
store_version="${store_ver%% *}"
store_date="${store_ver#* }"

run_json="$(gh run list --workflow="$WORKFLOW" --branch main --limit 1 --json databaseId,conclusion,headSha,createdAt 2>/dev/null || echo '[]')"
run_id="$(printf '%s' "$run_json" | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r[0]["databaseId"] if r else "")')"
run_concl="$(printf '%s' "$run_json" | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r[0]["conclusion"] if r else "")')"
run_sha="$(printf '%s' "$run_json" | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r[0]["headSha"][:7] if r else "")')"

echo "pubspec.yaml:        ${pubspec_ver}  (build ${pubspec_build})"
echo "Latest GitHub release: ${latest_tag:-?}"
if [ -n "$store_version" ]; then
  echo "App Store (live):    ${store_version}  released ${store_date}"
else
  echo "App Store (live):    lookup failed (offline, or app not found for ${BUNDLE_ID})"
fi
if [ -n "$run_id" ]; then
  echo "Last iOS Build (main): ${run_concl} @ ${run_sha}  (run ${run_id})"
  if [ "$run_concl" = "failure" ]; then
    reason="$(gh run view "$run_id" --log-failed 2>/dev/null | grep -o 'CFBundleShortVersionString \[[^]]*\][^.]*\.' | head -1 || true)"
    [ -n "$reason" ] && echo "  upload rejected: ${reason}"
  fi
fi
echo

# Verdict: pubspec must be strictly greater than the live store version.
if [ -z "$store_version" ]; then
  echo "VERDICT: unknown — could not read the App Store version."
  exit 2
fi
highest="$(printf '%s\n%s\n' "$pubspec_ver" "$store_version" | sort -V | tail -1)"
if [ "$pubspec_ver" = "$store_version" ] || [ "$highest" != "$pubspec_ver" ]; then
  IFS=. read -r maj min pat <<<"$store_version"
  next="${maj}.${min}.$((pat + 1))"
  echo "VERDICT: BUMP NEEDED — ${pubspec_ver} is not above the approved ${store_version}."
  echo "         The next push to main will fail at upload. Bump pubspec.yaml to ${next}+$((pubspec_build + 1))."
  exit 1
fi
echo "VERDICT: OK — ${pubspec_ver} is above the approved ${store_version}; uploads will be accepted."
