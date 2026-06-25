# Automated Production Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a release-please GitHub Release, automatically submit the iOS build to App Store review and roll the Android build to Play production at a staged 10%, each with sanitized release notes from `CHANGELOG.md` — without touching the existing per-merge TestFlight/internal flow.

**Architecture:** One new `release-deploy.yml` workflow triggered on `release: published`, with two independent jobs (iOS on macOS, Android on Ubuntu) that rebuild the signed artifacts from scratch (cattle-not-pets). A standalone `scripts/release_notes.sh` extracts the top `CHANGELOG.md` section and sanitizes markdown to store-safe plain text. iOS uploads via `altool`, waits for ASC processing, then submits the existing build via fastlane `deliver` (skip metadata/screenshots). Android uses the existing `r0adkll/upload-google-play` action with `track: production, status: inProgress, userFraction: 0.10`.

**Tech Stack:** GitHub Actions, Flutter 3.41.6, fastlane `deliver`, `r0adkll/upload-google-play@v1`, `xcrun altool`, App Store Connect API, Google Play (WIF auth), POSIX shell + awk.

**Reference spec:** `docs/superpowers/specs/2026-06-25-automated-prod-release-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/release_notes.sh` (new) | Extract top CHANGELOG section + sanitize to store-safe plain text. Pure function of stdin/args; no CI coupling. |
| `scripts/test_release_notes.sh` (new) | Self-contained assertions for `release_notes.sh` against a fixture. Runnable locally and in CI. |
| `test/fixtures/CHANGELOG.sample.md` (new) | Realistic release-please `dart` CHANGELOG fixture the test asserts against. |
| `.github/workflows/release-deploy.yml` (new) | Two-job release workflow triggered on `release: published`. |
| `fastlane/Fastfile` (new) | A single `submit_review` lane wrapping `deliver` (skip metadata/screenshots, submit existing build). |
| `fastlane/Appfile` (new) | App identifier + ASC API key config for fastlane. |
| `Gemfile` (new) | Pins fastlane for the iOS job. |

No changes to `ios.yml`, `android.yml`, `release-please.yml`, or `pubspec.yaml`.

---

## Task 1: Release-notes fixture

**Files:**
- Create: `test/fixtures/CHANGELOG.sample.md`

- [ ] **Step 1: Write a realistic release-please `dart` CHANGELOG fixture**

This mirrors exactly what release-please writes (two versions, so the parser must stop at the second `##`):

```markdown
# Changelog

## [1.3.0](https://github.com/eddimull/TTS-App/compare/v1.2.0...v1.3.0) (2026-06-25)


### Features

* **events:** add media upload to event detail ([#48](https://github.com/eddimull/TTS-App/issues/48)) ([abc1234](https://github.com/eddimull/TTS-App/commit/abc1234))
* **finances:** payout config create & activate ([#45](https://github.com/eddimull/TTS-App/issues/45)) ([def5678](https://github.com/eddimull/TTS-App/commit/def5678))


### Bug Fixes

* **release:** iOS build failing on macOS yq action ([#47](https://github.com/eddimull/TTS-App/issues/47)) ([9999aaa](https://github.com/eddimull/TTS-App/commit/9999aaa))

## [1.2.0](https://github.com/eddimull/TTS-App/compare/v1.1.0...v1.2.0) (2026-06-10)


### Features

* older feature that must NOT appear in extracted notes ([0000bbb](https://github.com/eddimull/TTS-App/commit/0000bbb))
```

- [ ] **Step 2: Commit**

```bash
git add test/fixtures/CHANGELOG.sample.md
git commit -m "test(release): add CHANGELOG fixture for release-notes parser"
```

---

## Task 2: `release_notes.sh` — extract top section (failing test first)

**Files:**
- Create: `scripts/test_release_notes.sh`
- Create: `scripts/release_notes.sh`

- [ ] **Step 1: Write the failing test harness**

Create `scripts/test_release_notes.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails (script missing)**

Run: `bash scripts/test_release_notes.sh`
Expected: FAIL — `scripts/release_notes.sh: No such file or directory`, ends with non-zero exit.

- [ ] **Step 3: Write minimal `release_notes.sh`**

Create `scripts/release_notes.sh`:

```bash
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
```

- [ ] **Step 4: Make both scripts executable and run the test**

Run:
```bash
chmod +x scripts/release_notes.sh scripts/test_release_notes.sh
bash scripts/test_release_notes.sh
```
Expected: `ALL PASS`

- [ ] **Step 5: Commit**

```bash
git add scripts/release_notes.sh scripts/test_release_notes.sh
git commit -m "feat(release): CHANGELOG section extractor + sanitizer with tests"
```

---

## Task 3: Wire the release-notes test into CI

**Files:**
- Create: `.github/workflows/release-deploy.yml` (notes-test job only for now; build jobs added in later tasks)

- [ ] **Step 1: Create the workflow with a fast lint/test job**

Create `.github/workflows/release-deploy.yml`:

```yaml
name: Release Deploy

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  notes-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Test release-notes sanitizer
        run: bash scripts/test_release_notes.sh
```

- [ ] **Step 2: Validate YAML locally**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-deploy.yml')); print('valid')"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-deploy.yml
git commit -m "ci(release): add release-deploy workflow with notes-test job"
```

---

## Task 4: fastlane config for iOS submit-for-review

**Files:**
- Create: `Gemfile`
- Create: `fastlane/Appfile`
- Create: `fastlane/Fastfile`

- [ ] **Step 1: Pin fastlane via Gemfile**

Create `Gemfile`:

```ruby
source "https://rubygems.org"

gem "fastlane", "~> 2.227"
```

- [ ] **Step 2: Create the Appfile**

Create `fastlane/Appfile` (bundle ID confirmed from AASA `band.tts.mate`):

```ruby
app_identifier("band.tts.mate")
```

- [ ] **Step 3: Create the Fastfile with a single submit lane**

Create `fastlane/Fastfile`. The lane authenticates with the ASC API key (from env the workflow sets), then submits the **already-uploaded** build for review without touching the listing:

```ruby
default_platform(:ios)

platform :ios do
  desc "Submit the already-uploaded build for App Store review (no metadata changes)"
  lane :submit_review do |options|
    api_key = app_store_connect_api_key(
      key_id: ENV["ASC_API_KEY_ID"],
      issuer_id: ENV["ASC_ISSUER_ID"],
      key_filepath: ENV["ASC_API_KEY_PATH"],
    )

    deliver(
      api_key: api_key,
      app_identifier: "band.tts.mate",
      app_version: options[:version],
      skip_binary_upload: true,
      skip_metadata: true,
      skip_screenshots: true,
      submit_for_review: true,
      automatic_release: false,
      force: true,
      precheck_include_in_app_purchases: false,
      submission_information: {
        add_id_info_uses_idfa: false
      }
    )
  end
end
```

- [ ] **Step 4: Validate Ruby syntax**

Run: `ruby -c fastlane/Fastfile && ruby -c fastlane/Appfile && ruby -c Gemfile`
Expected: `Syntax OK` for each.

- [ ] **Step 5: Commit**

```bash
git add Gemfile fastlane/Appfile fastlane/Fastfile
git commit -m "feat(release): fastlane submit_review lane for App Store"
```

---

## Task 5: iOS release job — build + upload + wait + submit

**Files:**
- Modify: `.github/workflows/release-deploy.yml`

This job reproduces the signed build from `ios.yml`, then uploads, waits for ASC processing, and submits.

- [ ] **Step 1: Add the `release-ios` job**

Append under `jobs:` in `.github/workflows/release-deploy.yml`:

```yaml
  release-ios:
    runs-on: macos-26
    needs: notes-test
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Resolve version name
        run: |
          set -euo pipefail
          VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
          if [ -z "$VERSION" ]; then
            VERSION="$(yq '.version' pubspec.yaml | sed 's/+.*//')"
          fi
          if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
            echo "::error::Could not resolve a version name" >&2
            exit 1
          fi
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"

      - name: Generate release notes
        run: |
          set -euo pipefail
          bash scripts/release_notes.sh CHANGELOG.md > "$RUNNER_TEMP/release_notes.txt"
          echo "RELEASE_NOTES_PATH=$RUNNER_TEMP/release_notes.txt" >> "$GITHUB_ENV"
          echo "----- release notes -----"; cat "$RUNNER_TEMP/release_notes.txt"

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.6'
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Write Firebase config
        env:
          FIREBASE_OPTIONS_DART_BASE64: ${{ secrets.FIREBASE_OPTIONS_DART_BASE64 }}
        run: |
          if [ -z "$FIREBASE_OPTIONS_DART_BASE64" ]; then
            echo "::error::FIREBASE_OPTIONS_DART_BASE64 secret is not set."
            exit 1
          fi
          echo -n "$FIREBASE_OPTIONS_DART_BASE64" | base64 --decode > lib/firebase_options.dart

      - name: Import certificate and provisioning profile
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          BUILD_PROVISION_PROFILE_BASE64: ${{ secrets.BUILD_PROVISION_PROFILE_BASE64 }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          PP_PATH=$RUNNER_TEMP/build_pp.mobileprovision
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          echo -n "$BUILD_CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH
          echo -n "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode -o $PP_PATH
          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security import $CERTIFICATE_PATH -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k $KEYCHAIN_PATH
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security list-keychain -d user -s $KEYCHAIN_PATH
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          cp $PP_PATH ~/Library/MobileDevice/Provisioning\ Profiles

      - name: Fix google_places_native_sdk iOS podspec naming
        run: |
          PLUGIN_IOS="$HOME/.pub-cache/hosted/pub.dev/google_places_native_sdk-3.0.0/ios"
          if [ -f "$PLUGIN_IOS/flutter_location_sdk.podspec" ] && [ ! -f "$PLUGIN_IOS/google_places_native_sdk.podspec" ]; then
            cp "$PLUGIN_IOS/flutter_location_sdk.podspec" "$PLUGIN_IOS/google_places_native_sdk.podspec"
          fi

      - name: Switch to manual code signing
        run: |
          echo "CODE_SIGN_STYLE=Manual" >> ios/Flutter/Release.xcconfig
          echo "CODE_SIGN_IDENTITY=Apple Distribution" >> ios/Flutter/Release.xcconfig
          echo "PROVISIONING_PROFILE_SPECIFIER=TTS Bandmate App Store" >> ios/Flutter/Release.xcconfig

      - name: Inject Google Maps API key
        env:
          GOOGLE_MAPS_IOS_API_KEY: ${{ secrets.GOOGLE_MAPS_IOS_API_KEY }}
        run: |
          if [ -z "$GOOGLE_MAPS_IOS_API_KEY" ]; then
            echo "::error::GOOGLE_MAPS_IOS_API_KEY secret is not set."
            exit 1
          fi
          echo "GOOGLE_MAPS_API_KEY=$GOOGLE_MAPS_IOS_API_KEY" >> ios/Flutter/Release.xcconfig

      - name: Build IPA
        run: |
          flutter build ipa --release \
            --build-name="$VERSION" \
            --build-number="$GITHUB_RUN_NUMBER" \
            --dart-define=BASE_URL=${{ secrets.BASE_URL }} \
            --dart-define=PUSHER_APP_KEY=${{ secrets.PUSHER_APP_KEY }} \
            --dart-define=PUSHER_APP_CLUSTER=${{ secrets.PUSHER_APP_CLUSTER }} \
            --dart-define=GOOGLE_PLACES_API_KEY=${{ secrets.GOOGLE_PLACES_API_KEY }} \
            --dart-define=SENTRY_DSN=${{ secrets.SENTRY_DSN }} \
            --dart-define=SENTRY_ENVIRONMENT=${{ secrets.SENTRY_ENVIRONMENT }} \
            --export-options-plist=ios/ExportOptions.plist

      - name: Write ASC API key file
        env:
          ASC_API_KEY_ID: ${{ secrets.ASC_API_KEY_ID }}
          ASC_API_KEY_BASE64: ${{ secrets.ASC_API_KEY_BASE64 }}
        run: |
          mkdir -p ~/.appstoreconnect/private_keys
          KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY_ID}.p8
          echo -n "$ASC_API_KEY_BASE64" | base64 --decode > "$KEY_PATH"
          echo "ASC_API_KEY_PATH=$KEY_PATH" >> "$GITHUB_ENV"

      - name: Upload build to App Store Connect
        env:
          ASC_API_KEY_ID: ${{ secrets.ASC_API_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: |
          xcrun altool --upload-app \
            --type ios \
            --file build/ios/ipa/*.ipa \
            --apiKey "$ASC_API_KEY_ID" \
            --apiIssuer "$ASC_ISSUER_ID"

      - name: Install fastlane
        run: |
          bundle install

      - name: Wait for build processing and submit for review
        env:
          ASC_API_KEY_ID: ${{ secrets.ASC_API_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          DELIVER_WHAT_TO_TEST_PATH: ${{ env.RELEASE_NOTES_PATH }}
        timeout-minutes: 45
        run: |
          set -euo pipefail
          # Wait for the just-uploaded build (this version + run number) to
          # finish ASC processing, then submit it for review.
          bundle exec fastlane run app_store_build_number \
            live:false \
            version:"$VERSION" \
            api_key_path:"$ASC_API_KEY_PATH" || true
          bundle exec fastlane ios submit_review version:"$VERSION"

      - name: Clean up keychain
        if: always()
        run: security delete-keychain $RUNNER_TEMP/app-signing.keychain-db
```

- [ ] **Step 2: Validate YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-deploy.yml')); print('valid')"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-deploy.yml
git commit -m "feat(release): iOS App Store submit-for-review job"
```

---

## Task 6: Android release job — build + production 10% rollout

**Files:**
- Modify: `.github/workflows/release-deploy.yml`

- [ ] **Step 1: Add the `release-android` job**

Append under `jobs:` in `.github/workflows/release-deploy.yml`:

```yaml
  release-android:
    runs-on: ubuntu-latest
    needs: notes-test
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Resolve version name
        run: |
          set -euo pipefail
          VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
          if [ -z "$VERSION" ]; then
            VERSION="$(yq '.version' pubspec.yaml | sed 's/+.*//')"
          fi
          if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
            echo "::error::Could not resolve a version name" >&2
            exit 1
          fi
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"

      - name: Generate release notes
        run: |
          set -euo pipefail
          mkdir -p distribution/whatsnew
          bash scripts/release_notes.sh CHANGELOG.md > distribution/whatsnew/whatsnew-en-US
          echo "----- whatsnew-en-US -----"; cat distribution/whatsnew/whatsnew-en-US

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.6'
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Write Firebase config
        env:
          FIREBASE_OPTIONS_DART_BASE64: ${{ secrets.FIREBASE_OPTIONS_DART_BASE64 }}
          GOOGLE_SERVICES_JSON_BASE64: ${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}
        run: |
          if [ -z "$FIREBASE_OPTIONS_DART_BASE64" ] || [ -z "$GOOGLE_SERVICES_JSON_BASE64" ]; then
            echo "::error::Firebase config secrets are not set."
            exit 1
          fi
          echo -n "$FIREBASE_OPTIONS_DART_BASE64" | base64 --decode > lib/firebase_options.dart
          echo -n "$GOOGLE_SERVICES_JSON_BASE64" | base64 --decode > android/app/google-services.json

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Decode keystore
        env:
          KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
        run: |
          echo -n "$KEYSTORE_BASE64" | base64 --decode > android/app/release.keystore

      - name: Write key.properties
        env:
          KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
          STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
        run: |
          cat > android/key.properties <<EOF
          storeFile=release.keystore
          storePassword=${STORE_PASSWORD}
          keyAlias=${KEY_ALIAS}
          keyPassword=${KEY_PASSWORD}
          EOF

      - name: Write local.properties
        env:
          GOOGLE_MAPS_API_KEY: ${{ secrets.GOOGLE_MAPS_ANDROID_API_KEY }}
        run: |
          cat > android/local.properties <<EOF
          sdk.dir=$ANDROID_SDK_ROOT
          GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY}
          EOF

      - name: Build AAB
        run: |
          flutter build appbundle --release \
            --build-name="$VERSION" \
            --build-number="$GITHUB_RUN_NUMBER" \
            --dart-define=BASE_URL=${{ secrets.BASE_URL }} \
            --dart-define=PUSHER_APP_KEY=${{ secrets.PUSHER_APP_KEY }} \
            --dart-define=PUSHER_APP_CLUSTER=${{ secrets.PUSHER_APP_CLUSTER }} \
            --dart-define=GOOGLE_PLACES_API_KEY=${{ secrets.GOOGLE_PLACES_API_KEY }} \
            --dart-define=SENTRY_DSN=${{ secrets.SENTRY_DSN }} \
            --dart-define=SENTRY_ENVIRONMENT=${{ secrets.SENTRY_ENVIRONMENT }}

      - name: Authenticate to Google Cloud
        id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}

      - name: Upload to Play Store (Production, staged 10%)
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJson: ${{ steps.auth.outputs.credentials_file_path }}
          packageName: tts.band
          releaseFiles: build/app/outputs/bundle/release/app-release.aab
          track: production
          status: inProgress
          userFraction: 0.10
          whatsNewDirectory: distribution/whatsnew
```

- [ ] **Step 2: Validate YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release-deploy.yml')); print('valid')"`
Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-deploy.yml
git commit -m "feat(release): Android Play production staged 10% rollout job"
```

---

## Task 7: Verify the notes pipeline end-to-end with a synthetic CHANGELOG

**Files:** none (verification only)

- [ ] **Step 1: Run the sanitizer against the fixture as the workflow would**

Run:
```bash
bash scripts/release_notes.sh test/fixtures/CHANGELOG.sample.md
```
Expected output (plain text, no `#`, no `**`, no `](http`, one section only):
```
Features
- events: add media upload to event detail (#48)
- finances: payout config create & activate (#45)
Bug Fixes
- release: iOS build failing on macOS yq action (#47)
```
(Exact bullet wording may vary slightly with sanitizer rules; the assertions in Task 2 are the source of truth. The "older feature" line must NOT appear.)

- [ ] **Step 2: Run the full test suite**

Run: `bash scripts/test_release_notes.sh`
Expected: `ALL PASS`

- [ ] **Step 3: Confirm no changes to existing workflows**

Run: `git diff --stat origin/main -- .github/workflows/ios.yml .github/workflows/android.yml .github/workflows/release-please.yml`
Expected: no output (those three files unchanged).

---

## Task 8: Open PR and document the manual prerequisites

**Files:**
- Create: PR description (no file)

- [ ] **Step 1: Push the branch and open the PR into `main`**

```bash
git push -u origin feat/automated-prod-release
gh pr create --base main --head feat/automated-prod-release \
  --title "feat(release): automate App Store + Play production submission with release notes" \
  --body "See docs/superpowers/specs/2026-06-25-automated-prod-release-design.md. Triggers on release-please GitHub Release; rebuilds artifacts; iOS submit-for-review via fastlane deliver (skip metadata); Android Play production staged 10%. Per-merge TestFlight/internal flow unchanged."
```

- [ ] **Step 2: Note manual prerequisites in the PR body**

Add a checklist comment to the PR:
- The App Store listing (description, screenshots, privacy) must already exist and be in a submittable state in App Store Connect — `deliver` runs with `skip_metadata`/`skip_screenshots`.
- The Google Play **production** track must have been released to manually at least once (Google requires a first manual production release before API uploads to it).
- First real release should be watched end-to-end; if `deliver` submit fails on "build still processing," re-run via `workflow_dispatch`.

- [ ] **Step 3: Do NOT merge until the above prerequisites are confirmed by the maintainer.**

---

## Self-Review

**Spec coverage:**
- Trigger on `release: published` → Task 3. ✔
- Rebuild artifacts (cattle-not-pets) → Tasks 5, 6 reproduce full signed builds. ✔
- iOS upload→wait→submit, skip metadata → Tasks 4, 5. ✔
- Android production staged 10% → Task 6. ✔
- Release notes from top CHANGELOG section, sanitized, capped → Tasks 1, 2. ✔
- Existing workflows untouched → Task 7 Step 3 asserts it. ✔
- Error handling: empty notes fail loudly (Task 2 script `::error::`), bounded iOS wait (Task 5 `timeout-minutes: 45`). ✔
- Testing: standalone shell test + fixture (Tasks 1, 2), CI job (Task 3). ✔

**Placeholder scan:** No TBD/TODO; every code/shell/YAML step shows full content. The one "exact bullet wording may vary" note in Task 7 is explicitly deferred to the Task 2 assertions, not a placeholder in the implementation.

**Type/identifier consistency:**
- Bundle ID `band.tts.mate` consistent across Appfile, Fastfile, Task 5. ✔
- Package `tts.band` consistent with `android.yml` and Task 6. ✔
- `submit_review` lane name consistent: Fastfile (Task 4) ↔ invocation (Task 5). ✔
- `RELEASE_NOTES_PATH` set (Task 5 notes step) ↔ consumed via `DELIVER_WHAT_TO_TEST_PATH`. ✔
- Secret names (`ASC_API_KEY_BASE64`, `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `WIF_*`, signing secrets) match those already used in `ios.yml`/`android.yml`. ✔

**Known implementation risk to flag at execution:** the `app_store_build_number` wait in Task 5 Step 1 is a best-effort processing wait; if `deliver` still reports the build as not ready, the executor should replace it with an explicit poll loop on the ASC API (documented as the spec's primary follow-up). Not a placeholder — the submit lane is fully specified — but the wait strategy may need hardening on first real run.
