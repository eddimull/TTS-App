# Spec — E2E tests for onboarding flows

**Date:** 2026-04-30
**Status:** Approved
**Related:** Future spec for deep-link auto-join feature (separate)

## Goal

Add four widget-level end-to-end tests covering the post-signup onboarding branches, plus refactor the existing `login_flow_widget_test.dart` to share a common test harness. Each new test drives the app from `/signup` to `/dashboard` and writes a PNG screenshot of the final state.

## Why now

The login flow is already covered. The signup-and-band-onboarding branches are not. The user wants visual regression coverage for these flows specifically because the next feature (deep-link invite auto-join) modifies signup-time behavior, and refactoring without tests on the surrounding flow is risky.

## Scope

Four tests, all in `test/onboarding_flows_widget_test.dart`:

1. **Signup → Go Solo → Dashboard**
2. **Signup → Create Band (skip invites) → Dashboard**
3. **Signup → Create Band (with invites) → Dashboard**
4. **Signup → Join via QR → Dashboard** (real `MobileScanner` widget, stubbed platform channel, synthetic barcode event)

Out of scope:
- Email-invite-link signup (a fifth test originally considered during brainstorming, separate from the four above) — current behavior is just `?email=` pre-fill, which is shallow. A meaningful test exists only after the deep-link auto-join feature ships, which is a separate spec.
- Login flow tests — already covered by `login_flow_widget_test.dart`.
- Backend/Laravel changes — none required.

## Architecture

### Shared harness — `test/helpers/test_harness.dart`

New file containing every test fixture currently inlined in `login_flow_widget_test.dart`:

- **`FakeSecureStorage`** — in-memory subclass of `SecureStorage`. Identical to the version currently in `login_flow_widget_test.dart`.
- **`StubAdapter`** — implements `HttpClientAdapter`. Constructor takes `Future<ResponseBody> Function(RequestOptions)`. The handler dispatches by `options.path`.
- **`StubApiClient`** — extends `ApiClient`, overrides the `dio` getter to return a pre-built Dio instance. Exposed publicly (no underscore) so multiple test files can use it.
- **`json(int status, Object body)`** — top-level helper that builds a `ResponseBody` from a JSON-encodable value.
- **`snap(WidgetTester tester, String name)`** — writes the current widget tree to `test/screenshots/<name>.png`. Walks the render tree to find the first `RenderRepaintBoundary` and rasterizes via `boundary.toImage(pixelRatio: 2.0)`. Wrapped in `tester.runAsync` so the rasterize completes outside the fake-async zone.
- **`stubConnectivityChannel()`** — registers mock handlers for `dev.fluttercommunity.plus/connectivity` (method channel, returns `['wifi']`) and `dev.fluttercommunity.plus/connectivity_status` (event channel, returns `null`). Called from `setUp`.
- **`Harness bootstrapApp({required Future<ResponseBody> Function(RequestOptions) handler, String initialLocation = '/login'})`** — returns a small record/struct:
  ```
  class Harness {
    final Widget widget;            // Configured ProviderScope(BandmateApp())
    final FakeSecureStorage storage;
    final RouteStorage routeStorage;
    final Map<String, List<dynamic>> capturedBodies;  // path → [parsed JSON, ...]
  }
  ```
  Internally: builds the `FakeSecureStorage`, mocks `SharedPreferences`, builds a Dio with `StubAdapter(handler)`, builds a `StubApiClient`, and assembles the `ProviderScope` with the four overrides currently inlined in `login_flow_widget_test.dart`.

### Test file — `test/onboarding_flows_widget_test.dart`

Single `void main()` containing:

- `TestWidgetsFlutterBinding.ensureInitialized()`
- `setUp(stubConnectivityChannel)`
- One `group('onboarding flows')` with four `testWidgets` blocks.

Each test follows this skeleton:

```
final harness = bootstrapApp(handler: (options) async {
  final path = options.path;
  if (path.endsWith(ApiEndpoints.mobileRegister)) return json(200, registerResponse);
  if (path.endsWith(ApiEndpoints.mobileMe)) return json(200, meResponse);
  // ... endpoint-specific stubs ...
  throw 'unstubbed endpoint: $path';
});

await tester.pumpWidget(harness.widget);
await tester.pumpAndSettle();

// Navigate to /signup, fill fields, tap, advance frames, repeat...

// Bounded pump to let the final redirect settle without pumpAndSettle hanging.
for (var i = 0; i < 30; i++) await tester.pump(const Duration(milliseconds: 50));

expect(await harness.storage.readToken(), isNotNull);
expect(find.text('Sign In'), findsNothing);
await snap(tester, '<test_slug>_dashboard');
```

### Refactor — `test/login_flow_widget_test.dart`

The existing file currently inlines every fixture. After this spec ships:
- Delete inline `FakeSecureStorage`, `StubAdapter`, `_StubApiClient`, `_json`, `_snap`, the connectivity-channel `setUp`.
- Import `test/helpers/test_harness.dart`.
- Replace the inline `ProviderScope` setup with `bootstrapApp(handler: ...)`.
- Keep the test name, assertions, and three snap calls unchanged.

Run `flutter test test/login_flow_widget_test.dart` after the refactor to confirm it still passes and the same three PNGs appear.

## Test details

### Test 1 — Signup → Go Solo → Dashboard

**Stubbed endpoints:**
| Endpoint | Method | Response |
|---|---|---|
| `mobileRegister` | POST | `{token: "tok", user: {id:1,...}, bands: []}` |
| `mobileBandsSolo` | POST | `{bands: [{id:10, name: "Eddie", is_owner: true}]}` |
| `mobileMe` | GET | `{user: {id:1,...}, bands: [{id:10,...}]}` |

**Flow:**
1. Bootstrap with `initialLocation: '/login'`, `pumpAndSettle`.
2. Tap "Sign up", `pumpAndSettle`. Now on `/signup`.
3. Enter text into the four CupertinoTextFields: name, email, password, confirm.
4. Tap "Create Account". Bounded pump. Land on `/bands` (path-select).
5. Assert the heading "How would you like to use Bandmate?" appears.
6. Tap "Go Solo". Bounded pump. Router auto-selects band 10 → `/dashboard`.
7. Assert `harness.storage.readToken() == "tok"`, login screen gone.
8. `snap(tester, 'solo_01_dashboard')`.

### Test 2 — Signup → Create Band (skip invites) → Dashboard

**Stubbed endpoints:**
| Endpoint | Method | Response |
|---|---|---|
| `mobileRegister` | POST | `{token: "tok", user, bands: []}` |
| `mobileCreateBand` | POST | `{band: {id:11, name: "The Eds", is_owner: true}}` |
| `mobileMe` | GET | `{user, bands: [{id:11,...}]}` |

**Flow:**
Signup as in test 1. On `/bands`, tap "Create a Band". On `/bands/create` step 1, type "The Eds" into the band-name field, tap "Next". On step 2, tap "Skip for now". Bounded pump. Land on `/dashboard`. Snap `create_skip_01_dashboard`.

### Test 3 — Signup → Create Band (with invites) → Dashboard

**Stubbed endpoints:** same as test 2, plus:
| Endpoint | Method | Response |
|---|---|---|
| `mobileBandInvite(11)` (`/api/mobile/bands/11/invite`) | POST | `{}` |

**Flow:**
Same as test 2 through step 1 ("Next"). On step 2: type `bandmate@example.com` into the email field, tap the `+` button (asserting the chip appears), tap "Done". Bounded pump. Land on `/dashboard`.

**Additional assertion:** the harness records request bodies for inspection. After the dashboard snap, parse the captured body for `mobileBandInvite(11)` as JSON and assert `body['emails']` equals `['bandmate@example.com']`.

Implementation: `bootstrapApp` returns a `Map<String, List<dynamic>> capturedBodies` (keyed by URL path, list because an endpoint can be hit multiple times). Inside `StubAdapter.fetch`, before calling the user-supplied handler, decode `requestStream` to UTF-8, JSON-parse it, and append to `capturedBodies[options.path]`. Tests read from `harness.capturedBodies[ApiEndpoints.mobileBandInvite(11)].first`.

Snap `create_invite_01_dashboard`.

### Test 4 — Signup → Join via QR → Dashboard

**Stubbed endpoints:**
| Endpoint | Method | Response |
|---|---|---|
| `mobileRegister` | POST | `{token: "tok", user, bands: []}` |
| `mobileBandsJoin` | POST | `{bands: [{id:12, name: "The Eds", is_owner: false}]}` |
| `mobileMe` | GET | `{user, bands: [{id:12,...}]}` |

**Flow:**
1. Signup as in test 1. On `/bands`, tap "Join a Band". On `/bands/join`, tap "Scan QR Code". The scanner widget mounts (`_scanning = true`).
2. Inject a synthetic barcode event via the `mobile_scanner` platform channels.
3. The scanner's `onDetect` callback fires, `setState(() => _scanning = false)` runs, `_joinWithKey("ABC123")` is invoked → `POST /bands/join` → refreshBands → router redirects to `/dashboard`.
4. Assert the captured body for `mobileBandsJoin` equals `{"key": "ABC123"}`.
5. Snap `join_qr_01_dashboard`.

**`mobile_scanner` channel stubbing — risk and mitigation:**
- The channel names and message format are not part of `mobile_scanner`'s public API. They may change between package versions.
- Before writing test 4, read `mobile_scanner`'s source under `~/.pub-cache/hosted/pub.dev/mobile_scanner-*/lib/src/` to identify the exact channel name(s) and the message envelope used to deliver `BarcodeCapture` events.
- If the channels can be stubbed, do so directly with `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` (method channel) and `setMockMessageHandler` for the event channel.
- If `mobile_scanner` proves unstubable (e.g., it uses a `MethodCodec` that requires native registration), test 4 falls back to plan B: extract a minimal injectable scanner-builder param on `JoinBandScreen` and pass a fake widget in the test that calls `onDetect` directly. Document this fallback in the test file.

## Error handling

- The handler in each test throws `'unstubbed endpoint: $path'` for any unmatched request. Tests fail loudly rather than getting silent 200s with empty bodies.
- The connectivity stub is set up via `setUp` so all four tests inherit it.
- Bounded `pump()` loops are used after every navigation that lands on a screen with continuous animations or streams (calendar widget, dashboard); `pumpAndSettle` is only used on screens known to quiesce (login, signup).

## Open questions / future work

- After test 4 is working, the next spec covers deep-link auto-join: the signup URL carries an invite key, the key persists through registration, and is redeemed automatically against `mobileBandsJoin` post-signup. That spec will replace the email-invite test we dropped.
- If `mobile_scanner` channel stubbing turns out to be brittle in CI, the fallback (injectable scanner-builder) becomes the long-term answer. Decision deferred until we see channel-stubbing in practice.

## Acceptance

- `flutter test test/onboarding_flows_widget_test.dart` passes — all four tests green.
- `flutter test test/login_flow_widget_test.dart` still passes after the harness refactor.
- `flutter analyze test/` reports zero issues.
- The four new PNGs and the three existing PNGs appear under `test/screenshots/` after a full run.
