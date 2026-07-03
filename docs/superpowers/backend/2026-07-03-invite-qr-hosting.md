# Invite QR Deep-Linking — tts.band Hosting Requirements

Serve these from the TTS Laravel app (PR targets `staging`). Until all three are
live and correctly served, the OS silently falls back to the browser even when
the app is installed.

## 1. Android App Links — `GET /.well-known/assetlinks.json`

- Content-Type `application/json`, HTTP 200, **no redirect**, short/no cache.

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "tts.band",
    "sha256_cert_fingerprints": ["<PLAY_APP_SIGNING_SHA256>"]
  }
}]
```

- `<PLAY_APP_SIGNING_SHA256>`: Play Console → App integrity → App signing →
  **app-signing** cert SHA-256. Add the **upload** cert fingerprint as a second
  array entry if sideloaded/internal-test builds must also verify.

## 2. iOS Universal Links — `GET /.well-known/apple-app-site-association`

- Content-Type `application/json`, HTTP 200, **no `.json` extension**, no redirect.

```json
{
  "applinks": {
    "apps": [],
    "details": [{ "appID": "<TEAM_ID>.band.tts.mate", "paths": ["/invite/*"] }]
  }
}
```

- `<TEAM_ID>`: Apple Developer → Membership → Team ID.
- Bundle ID `band.tts.mate` is fixed (from the iOS project).

## 3. Web fallback — `GET /invite/{key}`

For users WITHOUT the app installed (the OS opens this in a browser):
- Offer App Store + Play Store links ("Get the app").
- Optionally offer web-join for the browser.
- (Enhancement, not required: preserve `{key}` for deferred deep link so a
  freshly installed app auto-joins.)

## Verify after deploy
- `curl -I https://tts.band/.well-known/assetlinks.json` → 200, JSON, no redirect.
- `curl -I https://tts.band/.well-known/apple-app-site-association` → 200, JSON.
- Android: `adb shell pm verify-app-links --re-verify tts.band` then
  `adb shell pm get-app-links tts.band` shows `verified`.
- iOS: scan the QR on a device with the app installed → opens the app on the
  join screen (not Safari).
