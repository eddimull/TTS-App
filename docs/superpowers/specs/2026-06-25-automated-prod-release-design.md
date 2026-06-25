# Automated Production Release — Design

**Date:** 2026-06-25
**Status:** Proposed (awaiting review)
**Repo:** TTS-App (Flutter mobile)

## Goal

When release-please cuts a new version (`vX.Y.Z` tag + GitHub Release), automatically:

1. Submit the iOS build to **App Store review** (beyond TestFlight).
2. Roll the Android build out to **Google Play production** as a staged 10% rollout.
3. Attach **release notes** derived from `CHANGELOG.md` to both stores.

All of this **without touching** the existing per-merge flow (TestFlight + Play internal), and **without overwriting** the App Store Connect listing metadata.

## Non-goals

- Managing App Store listing metadata/screenshots from the repo. The ASC listing remains the source of truth; `deliver` only submits the build for review.
- Changing the existing `ios.yml` / `android.yml` build workflows' behavior on merge.
- Automating the human "release to 100%" decision for Play (stops at 10% staged).
- Releasing iOS to the public the instant Apple approves (Apple's manual-vs-auto-release setting on the version governs that; out of scope).

## Current state (verified)

- `ios.yml` (runs on `push: main`): builds signed IPA, uploads to TestFlight via `xcrun altool --upload-app`. No release notes. Bundle ID `band.tts.mate`, team `FBE5WVZKNK`.
- `android.yml` (runs on `push: main`): builds signed AAB, uploads to Play **internal** track via `r0adkll/upload-google-play` (`status: completed`). Package `tts.band`. Auth via Workload Identity Federation (`WIF_PROVIDER` / `WIF_SERVICE_ACCOUNT`).
- `release-please.yml` (runs on `push: main`): maintains release PR; on merge writes `CHANGELOG.md`, bumps `pubspec.yaml`, creates tag `vX.Y.Z` and a GitHub Release.
- Secrets already present: `ASC_API_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_BASE64`, all iOS signing secrets, all Android signing secrets, `WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT`, plus the dart-define secrets.

## Approach

**Approach B: a new, separate `release-deploy.yml` workflow**, triggered by the GitHub Release that release-please publishes. It **rebuilds** the signed artifacts from scratch (cattle-not-pets — deterministic, self-contained, no cross-workflow artifact passing) and submits them to production. The existing build workflows are untouched.

### Trigger

```yaml
on:
  release:
    types: [published]
  workflow_dispatch:   # manual re-run / dry-run safety valve
```

`release: published` fires exactly when release-please publishes the GitHub Release for a new tag — the natural release gate. `workflow_dispatch` allows manual re-trigger if a submission needs re-running.

### Jobs

Two independent jobs (iOS on `macos-26`, Android on `ubuntu-latest`), mirroring the build setup in the existing workflows. They do not depend on each other; a failure in one does not block the other.

#### Shared: release-notes derivation

A step (run per job, or a small composite) that:

1. Extracts the **top-most version section** from `CHANGELOG.md` — the block from the first `## [x.y.z]` (or `## x.y.z`) header down to the next `##` header. `awk`-based, no extra deps.
2. **Sanitizes** the markdown into store-safe plain text:
   - Drop `###`/`##` sub-headers → keep as plain lines or section labels.
   - Strip markdown links `[text](url)` → `text`.
   - Strip emphasis `**`, `*`, backticks.
   - Collapse list markers to `- `.
   - Cap total length (Apple "What to Test" / review notes limit is 4000 chars; truncate at a word boundary with a trailing ellipsis if exceeded).
3. Emits the sanitized text to a file the platform step consumes.

The sanitizer is a small, self-contained shell/awk script committed to the repo (e.g. `scripts/release_notes.sh`) so it is testable and identical across both jobs.

#### iOS job (`release-ios`)

1. Checkout (`fetch-depth: 0`), resolve version (same yq/git-describe step as `ios.yml`).
2. Reproduce the signed-build setup from `ios.yml`: Flutter, Firebase config, certificate/profile import, manual signing, Maps key, `flutter build ipa`.
3. Generate + sanitize release notes.
4. **Upload the build to App Store Connect.** `deliver` submits an *existing* build for review — it does not wait for a fresh upload to finish processing. So the IPA is first uploaded (via `altool --upload-app`, exactly as the existing TestFlight step does) and the job then **waits for ASC to finish processing** the new build before submitting. The wait can use `deliver`'s build-selection (`latest_build_number` against the resolved version) or a short poll/retry on the ASC API.
5. **Submit via fastlane `deliver`** (added only in this workflow):
   - Auth via existing ASC API key secrets (`ASC_API_KEY_*`).
   - `skip_binary_upload: true` — the binary was already uploaded in step 4; `deliver` only attaches notes + submits.
   - `skip_metadata: true`, `skip_screenshots: true` — does **not** touch the listing.
   - `submit_for_review: true`.
   - Set the build's "What to Test" / review notes from the sanitized file.
   - `force: true` (no interactive HTML preview in CI).
6. Keychain cleanup (`if: always()`).

> **Note on the upload→process→submit sequence:** this ordering (upload binary → wait for processing → submit existing build) is the single most failure-prone part of the iOS path, because ASC processing time is variable. The implementation plan must treat the wait as a first-class step with a timeout, not an afterthought.

Rationale for fastlane here: `altool` can upload a build but cannot create an App Store version or submit for review. `deliver` is the minimal tool that can, and with `skip_metadata`/`skip_screenshots` it is constrained to "attach notes + submit build," nothing else. fastlane is introduced **only** in this new workflow; the existing TestFlight path keeps using `altool`.

#### Android job (`release-android`)

1. Checkout, resolve version, reproduce the signed-build setup from `android.yml` (Flutter, Firebase config, JDK, keystore, key.properties, local.properties, `flutter build appbundle`).
2. Generate + sanitize release notes; write to `distribution/whatsnew/whatsnew-en-US` (the layout `r0adkll/upload-google-play` expects via `whatsNewDirectory`).
3. Authenticate to Google Cloud (WIF, same as `android.yml`).
4. **Upload via `r0adkll/upload-google-play`** (same action already trusted):
   - `track: production`
   - `status: inProgress`, `userFraction: 0.10` (staged 10% rollout)
   - `whatsNewDirectory: distribution/whatsnew`
   - `packageName: tts.band`

## Data flow

```
release-please merges release PR
  → bumps pubspec, writes CHANGELOG.md, creates tag vX.Y.Z
  → publishes GitHub Release  ──────────────► triggers release-deploy.yml
                                                  │
            ┌─────────────────────────────────────┴─────────────────────────────────┐
            │ release-ios (macos)                    │ release-android (ubuntu)        │
            │  build signed IPA                      │  build signed AAB               │
            │  extract+sanitize CHANGELOG top section│  extract+sanitize → whatsnew/   │
            │  fastlane deliver (submit for review,  │  upload-google-play             │
            │    skip metadata, notes attached)      │    track: production            │
            │                                        │    status: inProgress 10%       │
            └────────────────────────────────────────┴─────────────────────────────────┘
```

Per-merge flow (`ios.yml` / `android.yml`) is unchanged: every merge to `main` still ships to TestFlight + Play internal.

## Error handling

- **Release-notes extraction finds nothing** (no CHANGELOG section): fail the notes step with `::error::` rather than submitting empty notes. A release should always have notes.
- **Sanitized notes exceed limit:** truncate at word boundary + ellipsis (do not fail).
- **iOS submission fails** (e.g. Apple rejects metadata state, build still processing): job fails loudly; surfaced as a failed workflow run. Re-runnable via `workflow_dispatch`. The upload→wait-for-processing→submit sequence (see iOS job step 4–5) is the expected failure point; the wait step has a bounded timeout so the job fails fast rather than hanging if processing stalls.
- **Android 10% rollout:** `r0adkll` failure (e.g. version code already exists) fails the job; re-runnable.
- **Jobs are independent:** iOS failure does not block Android shipping, and vice versa.

## Testing / verification

- `scripts/release_notes.sh` is unit-testable in isolation: feed it a sample `CHANGELOG.md`, assert the sanitized output (no markdown, under cap, correct section). Add a small test fixture + a `bats`-style or plain shell assertion run locally (and optionally a CI lint job).
- The workflow itself is verified via `workflow_dispatch` dry-run on a release tag before trusting it on a real release. For the very first real release, watch the run end-to-end.
- YAML validated (parses) before commit.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| `deliver` overwrites ASC listing | `skip_metadata: true`, `skip_screenshots: true` — submits build only |
| Apple review rejection becomes a silent CI failure | Job fails loudly; `workflow_dispatch` re-run; first release watched manually |
| Play 100% instant blast radius | Staged `userFraction: 0.10`; human bumps to 100% in Play Console |
| Production submit on every merge | Triggered by `release: published` only — feature merges never reach this workflow |
| fastlane introduced to a fastlane-less repo | Scoped to this one workflow; existing `altool` TestFlight path untouched |
| Markdown notes rejected by Apple | Sanitizer strips markdown + caps length before submission |

## New files / changes

- `.github/workflows/release-deploy.yml` (new) — the two-job release workflow.
- `scripts/release_notes.sh` (new) — CHANGELOG section extractor + sanitizer.
- `test/release_notes_test.*` (new) — fixture + assertions for the sanitizer.
- iOS job uses fastlane `deliver`; a minimal `fastlane/` config (Appfile/Fastfile or inline `deliver` invocation) scoped to this workflow.
- No changes to `ios.yml`, `android.yml`, `release-please.yml`, or `pubspec.yaml`.

## Open follow-ups (not blocking)

- `deliver` may require waiting for ASC build processing before `submit_for_review`; add a wait/retry if the first runs show flakiness.
- Localized release notes (only `en-US` initially).
- Optionally promote Play 10% → 100% automatically after a soak period (separate scheduled workflow; out of scope here).
