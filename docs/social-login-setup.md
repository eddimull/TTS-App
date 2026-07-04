# Social login — credential setup checklist

This is the list of steps only an account owner (Google Cloud Console / Apple
Developer / Facebook Developers admin access) can perform. Everything else
(mobile UI, repository/SDK wiring, backend endpoints) is already implemented
in this repo and in `eddimull/TTS#505`. Real IDs from this checklist replace
the placeholders left by the platform-config commit.

App identifiers (verified in the repo, not `com.tts.bandmate`):
- Android `applicationId` / `namespace`: `tts.band` (`android/app/build.gradle.kts`)
- iOS `PRODUCT_BUNDLE_IDENTIFIER`: `band.tts.mate` (`ios/Runner.xcodeproj/project.pbxproj`)

## Google (Google Cloud Console → APIs & Services → Credentials)
- [ ] OAuth client (Web) → `GOOGLE_SIGNIN_CLIENT_ID` / `GOOGLE_SIGNIN_CLIENT_SECRET` (TTS `.env`),
      also passed to the mobile app at build time as
      `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>` (read in
      `lib/core/config/app_config.dart`)
- [ ] OAuth client (Android): package `tts.band` + release AND debug SHA-1.
      No manifest changes needed on the Flutter side — `android/app/google-services.json`
      carries the Android client config; just make sure the SHA-1 fingerprints
      are registered against this client in the console.
- [ ] OAuth client (iOS): bundle id `band.tts.mate` → its client id replaces
      `IOS_GOOGLE_CLIENT_ID_PLACEHOLDER` in two places in `ios/Runner/Info.plist`:
      - `GIDClientID` string value
      - the reversed-client-id URL scheme inside `CFBundleURLTypes` →
        `CFBundleURLSchemes` (`com.googleusercontent.apps.<client id>`)
- [ ] `GOOGLE_SIGNIN_ALLOWED_CLIENT_IDS` (TTS `.env`) = web client id AND iOS
      client id, comma-separated. Android id_tokens carry the web id as `aud`
      (via `serverClientId`); iOS id_tokens are typically minted for the iOS
      client id instead — the backend whitelist needs both.
- [ ] Authorized redirect URI on the web client: `https://tts.band/auth/google/callback`
      (+ staging URL)

## Apple (developer.apple.com)
- [ ] Enable "Sign in with Apple" capability on the App ID (`band.tts.mate`).
      `ios/Runner/Runner.entitlements` already declares
      `com.apple.developer.applesignin` (`Default`) — this just needs the
      capability enabled on the App ID in the portal to match.
- [ ] Create a Services ID (web) with return URL
      `https://tts.band/auth/apple/callback` → `APPLE_SERVICES_CLIENT_ID`
- [ ] Create a Sign in with Apple key (.p8). The backend mints the client
      secret automatically from the key material — set these once and forget:
      - `APPLE_PRIVATE_KEY_BASE64` = `base64 -w0 AuthKey_XXXX.p8`
      - `APPLE_KEY_ID` (from the Keys page)
      - `APPLE_TEAM_ID` (top-right of the developer portal)
      (A static `APPLE_CLIENT_SECRET` JWT still works as a fallback when the
      trio is unset, but it expires ≤ 6 months — prefer the trio.)
- [ ] `APPLE_SIGNIN_ALLOWED_CLIENT_IDS` = app bundle id (`band.tts.mate`) +
      Services ID (comma-separated)

## Facebook (developers.facebook.com)
- [ ] Create app, add "Facebook Login" product → `FACEBOOK_CLIENT_ID` / `FACEBOOK_CLIENT_SECRET`
- [ ] Enable Settings → Advanced → "Require App Secret"
- [ ] Add Android platform (package `tts.band` + key hashes) and iOS platform
      (bundle id `band.tts.mate`)
- [ ] Replace the placeholders left by the platform-config commit:
      - `android/app/src/main/res/values/strings.xml`:
        `facebook_app_id` (`FACEBOOK_APP_ID_PLACEHOLDER`),
        `facebook_client_token` (`FACEBOOK_CLIENT_TOKEN_PLACEHOLDER`),
        `fb_login_protocol_scheme` (`fbFACEBOOK_APP_ID_PLACEHOLDER` — the `fb`
        prefix stays, only the numeric app id portion changes)
      - `ios/Runner/Info.plist`:
        `FacebookAppID` (`FACEBOOK_APP_ID_PLACEHOLDER`),
        `FacebookClientToken` (`FACEBOOK_CLIENT_TOKEN_PLACEHOLDER`), and the
        `fbFACEBOOK_APP_ID_PLACEHOLDER` entry inside `CFBundleURLTypes` →
        `CFBundleURLSchemes`
- [ ] Valid OAuth redirect URI: `https://tts.band/auth/facebook/callback` (+ staging)
- [ ] Switch the app to Live mode (app review) before public rollout

## Backend env (staging + prod)
All the `GOOGLE_SIGNIN_*` / `APPLE_*` / `FACEBOOK_*` vars from `.env.example`
in the TTS repo (see `eddimull/TTS#505`).

## After credentials land
- [ ] Rebuild with `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`
- [ ] Use the `run-on-device` skill to verify Google sign-in on the Android
      phone against the local backend (requires the debug SHA-1 registered
      above)
- [ ] Apple/Facebook and iOS verification require credentials/hardware not
      currently available — track as a follow-up if still blocked
