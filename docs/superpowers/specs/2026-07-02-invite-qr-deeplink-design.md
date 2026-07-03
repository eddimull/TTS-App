# Invite QR Deep-Linking Design

**Date:** 2026-07-02
**Branch:** `feat/invite-qr-deeplink`
**Status:** Approved, ready for planning

## Problem

The band-invite QR code currently encodes a **bare invite key** string (e.g. `abc123`). A
phone's default camera app cannot act on a bare string, so scanning the QR outside the app's
own in-app scanner does nothing. We want the QR to open the TTS Bandmate app (or fall back to
the website) when scanned by any camera.

## Approach

Encode the QR as an **HTTPS App Link / Universal Link**: `https://tts.band/invite/<key>`.

- If the app is installed, Android App Links / iOS Universal Links hand the URL to the app,
  which routes to the join flow.
- If the app is not installed, the OS opens `https://tts.band/invite/<key>` in the browser,
  where the website provides a fallback (get-the-app page and/or web join).
- The app's own in-app scanner and manual-code entry keep working, accepting **either** a raw
  key (old QRs, typed codes) or an `/invite/<key>` URL.

Deep links are received via the `app_links` package (cold-start link + live link stream),
which supports Android App Links, iOS Universal Links, custom schemes, and web.

## Auth-gated join

When an unauthenticated user opens `/invite/<key>`:
1. Stash the key in a `pendingInviteKeyProvider`.
2. Redirect to `/login`.
3. After **any** successful authentication, the auth flow consumes the pending key, calls
   `joinBand(key)`, clears the pending state, and proceeds to the dashboard.

The post-login side effect is triggered via the **router listener** pattern
(`routerDelegate.addListener`), NOT inside `redirect` — per project convention that redirect
side effects break navigation.

This design is auth-method-agnostic: the key is consumed after any successful auth, so future
social logins work with it unchanged.

## Components (all in this Flutter repo)

### 1. QR content — `lib/features/band_settings/screens/widgets/invite_section.dart`
- Encode `https://tts.band/invite/$inviteKey` in `QrImageView.data`.
- Share the same URL via `Share.share(...)` instead of the bare key.
- The invite host comes from a new `AppConfig.inviteBaseUrl` constant (`https://tts.band`),
  not hardcoded in the widget.

### 2. Key extraction helper — `lib/features/bands/data/invite_key.dart` (new)
- `String? extractInviteKey(String input)`: returns the key from either a raw key string or a
  `https://tts.band/invite/<key>` URL (tolerant of trailing slashes, extra query params).
  Returns `null` for unparseable input.
- Used by `join_band_screen.dart` for both the scanner `onDetect` and manual submit, and by the
  deep-link service.

### 3. Deep-link service — `lib/core/deeplink/deep_link_service.dart` (new)
- Wraps `app_links`: reads `getInitialLink()` (cold start) and subscribes to `uriLinkStream`
  (warm links).
- On an `/invite/<key>` URI, extract the key and route to `/invite/:key`.
- Initialized once at app startup (in `app.dart`) and wired to the GoRouter instance.

### 4. Pending-invite provider — `lib/features/bands/providers/pending_invite_provider.dart` (new)
- Holds an optional invite key (`StateProvider<String?>` or a tiny notifier).
- Set on deep-link when unauthenticated; consumed once after successful auth; cleared after use.

### 5. GoRouter route — `lib/core/config/router.dart`
- Add `/invite/:key`.
- Handler: if authenticated → `joinBand(key)` then dashboard (surface success/failure); if not
  authenticated → set `pendingInviteKeyProvider`, redirect to `/login`.
- The post-login consume-and-join runs in the existing router listener, not in `redirect`.

### 6. Scanner/manual entry — `lib/features/bands/screens/join_band_screen.dart`
- Route both the scanned `rawValue` and the typed code through `extractInviteKey(...)` before
  calling `joinBand`. Preserves backward compatibility with existing bare-key QRs.

### 7. iOS native config — `ios/Runner/Runner.entitlements`
- Add `applinks:tts.band` and `applinks:www.tts.band` alongside the existing `webcredentials:`
  entries. Required for Universal Links.

### 8. Android native config — `android/app/src/main/AndroidManifest.xml`
- The existing `autoVerify` App Link intent-filter already matches the whole `tts.band` host,
  so `/invite/*` is already covered. **No change required.**

### 9. Web
- The same `/invite/:key` GoRouter route handles the PWA/browser case. No extra work.

## Out of scope — backend/hosting (user handles separately)

End-to-end deep-linking requires the `tts.band` site to host:
- `/.well-known/assetlinks.json` — Android App Links verification (SHA-256 signing cert
  fingerprints + package name).
- `/.well-known/apple-app-site-association` — iOS Universal Links (app ID + `/invite/*` path).
- A web `/invite/<key>` landing/fallback page (get-the-app and/or web join).

**Until these are hosted, the OS will not hand the link to the app.** The Flutter changes are
complete and correct independently; they are simply gated on this hosting for full end-to-end
behavior. The in-app scanner (which reads the URL directly) works regardless.

## Testing

Following the existing `ProviderContainer` + fake pattern (no widget/golden tests):
- `extractInviteKey`: raw key, full URL, URL with trailing slash, URL with query params, and
  garbage input → `null`.
- Pending-invite provider: set → consume returns the key and clears it; consume when empty →
  `null`.
- Deep-link routing decision: authed path (join + dashboard) vs unauthed path (stash + login),
  using a fake router/container.

## Follow-ups (not this branch)

- **Social logins** — orthogonal feature; the pending-invite flow already supports it since the
  key is consumed after any successful auth. Ship as its own spec/branch afterward.
- **Backend hosting** — the `.well-known` files and web fallback page (above).
