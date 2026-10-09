---
name: check-store-version
description: Check whether the version in pubspec.yaml can still be uploaded to App Store Connect, or needs a bump because that version is already approved. Use before a TestFlight build, after an iOS Build failure mentioning CFBundleShortVersionString, after a release-please release, or whenever asked whether the app version needs bumping.
---

# Check whether the app version needs a bump

Apple rejects any upload whose `CFBundleShortVersionString` is not **higher
than the version already approved** for the app. The iOS Build workflow
(`.github/workflows/ios.yml`) uploads **every push to `main`** to TestFlight
labelled with the `pubspec.yaml` version (`X.Y.Z` — the build number comes
from the run number). So once a version is approved, every push to `main`
fails at the upload step until `pubspec.yaml` moves past it. The failure
text is:

> This bundle is invalid. The value for key CFBundleShortVersionString
> [1.28.0] in the Info.plist file must contain a higher version than that of
> the previously approved version.

## Run the check

```bash
.claude/skills/check-store-version/scripts/check_store_version.sh
```

It prints the pubspec version, the latest GitHub release, the version live
on the App Store (public iTunes lookup for `band.tts.mate`, no credentials),
the last iOS Build result on `main` (with the rejection line if it failed),
and a verdict. Exit code 0 = OK, 1 = bump needed, 2 = couldn't tell.

Example of the bump-needed case:

```
pubspec.yaml:        1.28.1  (build 51)
Latest GitHub release: v1.28.1
App Store (live):    1.28.1  released 2026-10-07T16:35:09Z
Last iOS Build (main): success @ 7236465  (run 37544978560)

VERDICT: BUMP NEEDED — 1.28.1 is not above the approved 1.28.1.
         The next push to main will fail at upload. Bump pubspec.yaml to 1.28.2+52.
```

## How versions move in this repo

- **release-please** cuts releases from conventional commits on `main`
  (`feat:` → minor, `fix:` → patch; `chore:`/`docs:`/`test:` make no release).
  Merging its `chore(main): release X.Y.Z` PR sets `pubspec.yaml`, tags
  `vX.Y.Z` and runs `release-deploy.yml`, which builds and **submits to the
  stores**. Do not merge it just to get a build.
- For a **TestFlight build without a store submission**, bump `version:` in
  `pubspec.yaml` by hand on a `chore/bump-X.Y.Z` branch and open a PR to
  `main` — see #152 (1.28.0) and #160 (1.28.1). Use the next patch version
  and the next build number; release-please will reuse that version for its
  next release PR.
- The bump is only needed once per approved version. Pushes to `main` between
  approvals upload fine as long as the pubspec version stays above the live
  one.

## When the script says BUMP NEEDED

1. Confirm with the person — a bump is a repo change and starts a new
   TestFlight train.
2. `git switch -c chore/bump-X.Y.Z origin/main`, edit the single `version:`
   line in `pubspec.yaml` to the suggested value, commit as
   `Bump version to X.Y.Z+N`, push, open a PR to `main` titled the same.
3. Once merged, the push-to-main iOS Build uploads the new version to
   TestFlight; the Android Build uploads to the internal track regardless
   (Play keys builds by `versionCode`, which is the run number, so Android
   never needs this bump).

## Limits

- The iTunes lookup shows the version **live** on the App Store. A version
  that is approved but held for manual release (`Pending Developer Release`)
  is not visible to it, and Apple still rejects uploads at or below it. If a
  rejection happens while the script says OK, that is why — bump anyway.
  Reading that state needs the App Store Connect API key, which only CI has
  (`ASC_API_KEY_ID` / `ASC_ISSUER_ID` / `ASC_API_KEY_BASE64` secrets).
- Google Play tracks can be dumped with
  `gh workflow run play-track-inspect.yml` then `gh run view --log` on the run.
