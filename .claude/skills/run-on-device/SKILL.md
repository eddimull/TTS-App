---
name: run-on-device
description: Run the TTS Bandmate Flutter app on the physical Android phone against the local Laravel backend, log in, and drive to a screen. Use when asked to run/launch/test/screenshot the app on a real device, verify a UI change on-device, or reproduce something against local data.
---

# Run TTS Bandmate on the physical Android device

Launches the app on the connected Android phone, tunnels it to the local
HTTPS dev backend, gets past the dev TLS cert, and authenticates — the full
path verified to work. Web/Linux desktop are faster for pure-UI checks
(`flutter run -d chrome|linux`); use this when you specifically need the
**real device** against **real local data** (login, bookings, etc.).

## The one thing that will waste your time

The app talks to `https://localhost:8710` (an **mkcert** dev cert). The phone
does **not** trust your mkcert CA, so Dio's TLS validation fails. The failure
is **silent**: `auth_provider.dart`'s `checkAuth`/`login` swallow it in
`catch (_)` and emit `AuthUnauthenticated`, so the UI just bounces back to
`/welcome` with no error. Symptom in logs: `authState` cycling
`AuthLoading → AuthUnauthenticated` forever.

**Do NOT try to fix this by installing the mkcert CA on the device.** That was
tried and failed (Android user-CA trust + `network_security_config` is fiddly
and hard to verify without root). The reliable fix is already in the code: a
`kDebugMode`-gated `badCertificateCallback` in
`lib/core/network/api_client.dart` that accepts any cert in **debug builds
only** (never ships in release). If that block is gone, re-add it before
running — it is what makes on-device login work.

```dart
// lib/core/network/api_client.dart, inside _buildDio() after creating `dio`
if (kDebugMode) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    },
  );
}
// needs: import 'dart:io'; import 'package:dio/io.dart';
//        import 'package:flutter/foundation.dart';
```

## Known-good environment (this machine)

- Device serial: `R5CR60PRF6Y` (Samsung SM G998U). Discover with `flutter devices`.
- adb: `/home/eddie/Android/sdk/platform-tools/adb` (Flutter does NOT bundle
  adb; `which adb` may be empty — use the SDK path). The SDK root is in
  `~/.config/flutter/settings` (`"android-sdk"`); adb is at
  `<sdk>/platform-tools/adb`.
- Backend: local Laravel on `https://localhost:8710`. Confirm it's up first:
  `curl -sk -o /dev/null -w '%{http_code}\n' https://localhost:8710` → `200`.
- Dart-defines come from `.dart_defines/local.json` (gitignored; has BASE_URL,
  Sentry, Google keys). The VS Code launch config uses the same file.

## Procedure

1. **Pre-flight.** Confirm the bad-cert block exists in `api_client.dart`
   (`grep -n badCertificateCallback lib/core/network/api_client.dart`).
   Confirm the backend responds 200 (curl above). Confirm the device is
   attached (`flutter devices`).

2. **adb reverse** so the phone's `localhost:8710` reaches your machine. This
   drops whenever the device disconnects — re-arm it before each launch:
   ```bash
   ADB=/home/eddie/Android/sdk/platform-tools/adb
   "$ADB" reverse tcp:8710 tcp:8710
   "$ADB" shell svc power stayon usb   # keep screen awake; prevents mid-session USB drop
   ```

3. **Launch** in the background (build+install is 1-2 min):
   ```bash
   flutter run -d R5CR60PRF6Y --dart-define-from-file=.dart_defines/local.json
   ```
   Run it with `run_in_background: true` and watch the output file. A code or
   manifest change needs a full relaunch; pure Dart logic changes can hot
   restart (`R`).

4. **Wait for readiness, not a timer.** Watch the log file with a Bash
   `until grep -q ...` loop (one notification when ready) rather than polling.
   Terminal signals to grep for:
   - launched: `Flutter run key commands` / `Syncing files to device`
   - **login success**: `authState=AuthAuthenticated`, router moves
     `/welcome → /bands` (or `/dashboard`)
   - trouble: `HandshakeException`, `SocketException`, `Connection refused`,
     `Gradle task ... failed`, `Lost connection to device`

5. **Drive it.** Ask the user to log in + navigate, and confirm from the
   router logs (`[Router] redirect fired | location=...`). The booking-detail
   screen is `location=/bookings/<bandId>/<bookingId>` — that's the
   PAYMENTS/PAYOUT/CONTACTS/CONTRACT menu. Also watch for `RenderFlex
   overflowed` / `EXCEPTION CAUGHT` to catch layout regressions.

## Gotchas seen in practice

- **`Lost connection to device` mid-session** = the `flutter run` session
  detached (screen locked / USB hiccup); the app usually keeps running. Step 2's
  `stayon usb` prevents most of these. Re-arm `adb reverse` and relaunch.
- **`pkill -f "flutter run ..."`** to stop a launch returns non-zero if nothing
  matched, which aborts an `&&` chain — run cleanup commands on separate lines.
- **adb `&&` chaining**: `adb reverse ... && adb shell ...` — if the first
  succeeds but you chained off a `pkill` that failed, nothing runs. Keep adb
  setup commands unchained.
- **`curl` on the phone uses its own CA bundle**, not Android's trust store, so
  `curl` succeeding/failing tells you about the network path, not whether the
  *app* trusts the cert.

## Teardown (when done testing)

```bash
ADB=/home/eddie/Android/sdk/platform-tools/adb
"$ADB" reverse --remove tcp:8710
"$ADB" shell svc power stayon false
```
Stop the background `flutter run` task. The debug bad-cert block stays in the
code (it's debug-only) unless the user wants it stripped before committing.
