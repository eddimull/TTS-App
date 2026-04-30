# Onboarding E2E Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four widget-level E2E tests covering signup → onboarding branches (solo, create-band-skip, create-band-with-invites, join-via-QR), each ending on `/dashboard` with a screenshot. Refactor existing login flow test to share a common harness.

**Architecture:** A single shared harness file (`test/helpers/test_harness.dart`) holds every fixture currently inlined in `login_flow_widget_test.dart` (FakeSecureStorage, StubAdapter, StubApiClient, screenshot helper, connectivity stub, bootstrapApp). Four new tests in `test/onboarding_flows_widget_test.dart` consume the harness. The existing login test is migrated to use the harness without changing assertions or screenshot output.

**Tech Stack:** Flutter 3.x, Riverpod 3.x, Dio 5.x, GoRouter 17.x, mobile_scanner 6.0.11, flutter_test, dart:ui for image rasterization.

---

## File Structure

**Create:**
- `test/helpers/test_harness.dart` — shared fixtures (Tasks 1–7)
- `test/onboarding_flows_widget_test.dart` — four new tests (Tasks 9–12)

**Modify:**
- `test/login_flow_widget_test.dart` — strip inline fixtures, import harness (Task 8)

**Untouched:**
- `lib/**` — no production code changes in this plan
- `pubspec.yaml` — no new dependencies (mobile_scanner is already a runtime dep)

---

## Task 1: Create harness file with FakeSecureStorage

**Files:**
- Create: `test/helpers/test_harness.dart`

- [ ] **Step 1: Create the helpers directory and harness file**

Run:
```bash
mkdir -p test/helpers
```

Then create `test/helpers/test_harness.dart` with this content:

```dart
// Shared test harness for widget-level E2E tests. Anything reusable across
// test files lives here.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:tts_bandmate/core/storage/secure_storage.dart';

/// In-memory replacement for [SecureStorage]. Bypasses [FlutterSecureStorage]
/// entirely — the super constructor receives a real instance but every method
/// is overridden.
class FakeSecureStorage extends SecureStorage {
  FakeSecureStorage() : super(const FlutterSecureStorage());

  final Map<String, String?> _map = {};

  @override
  Future<String?> readToken() async => _map['auth_token'];
  @override
  Future<void> writeToken(String token) async => _map['auth_token'] = token;
  @override
  Future<void> deleteToken() async => _map.remove('auth_token');

  @override
  Future<String?> readBandId() async => _map['selected_band_id'];
  @override
  Future<void> writeBandId(String bandId) async =>
      _map['selected_band_id'] = bandId;
  @override
  Future<void> deleteBandId() async => _map.remove('selected_band_id');

  @override
  Future<String?> readUser() async => _map['current_user_json'];
  @override
  Future<void> writeUser(String userJson) async =>
      _map['current_user_json'] = userJson;

  @override
  Future<void> clear() async => _map.clear();
}
```

- [ ] **Step 2: Confirm the file analyzes cleanly**

Run:
```bash
flutter analyze test/helpers/test_harness.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add test/helpers/test_harness.dart
git commit -m "test: add FakeSecureStorage to shared test harness"
```

---

## Task 2: Add StubAdapter and json helper

**Files:**
- Modify: `test/helpers/test_harness.dart`

- [ ] **Step 1: Append StubAdapter and json helper**

Add these imports at the top of `test/helpers/test_harness.dart` (alongside the existing imports):

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
```

Then append to the file:

```dart
/// A Dio [HttpClientAdapter] that delegates every request to a user-supplied
/// async handler. Use this to stub HTTP responses by URL path.
///
/// Before invoking the handler, the request body (if present) is decoded as
/// UTF-8 and JSON-parsed, then appended to [capturedBodies] under the
/// request's path. Tests can read the captured body to assert on what the app
/// actually sent.
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this._handler, {Map<String, List<dynamic>>? capturedBodies})
      : _capturedBodies = capturedBodies;

  final Future<ResponseBody> Function(RequestOptions options) _handler;
  final Map<String, List<dynamic>>? _capturedBodies;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_capturedBodies != null && requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      if (chunks.isNotEmpty) {
        try {
          final parsed = jsonDecode(utf8.decode(chunks));
          _capturedBodies[options.path] =
              [...?_capturedBodies[options.path], parsed];
        } catch (_) {
          // Non-JSON body — ignore for capture purposes.
        }
      }
    }
    return _handler(options);
  }
}

/// Build a Dio [ResponseBody] from a JSON-encodable Dart value.
ResponseBody json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(
    encoded,
    status,
    headers: {
      'content-type': ['application/json'],
    },
  );
}
```

- [ ] **Step 2: Confirm the file analyzes cleanly**

Run:
```bash
flutter analyze test/helpers/test_harness.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add test/helpers/test_harness.dart
git commit -m "test: add StubAdapter and json helper to test harness"
```

---

## Task 3: Add StubApiClient

**Files:**
- Modify: `test/helpers/test_harness.dart`

- [ ] **Step 1: Add the import**

Add to the import block:

```dart
import 'package:tts_bandmate/core/network/api_client.dart';
```

- [ ] **Step 2: Append StubApiClient**

Append to the file:

```dart
/// An [ApiClient] that uses a pre-built Dio (typically wired to a [StubAdapter])
/// instead of the real one. Tests construct one of these and pass it to the
/// `apiClientProvider` override.
class StubApiClient extends ApiClient {
  StubApiClient({required super.storage, required Dio dio}) : _stubDio = dio;

  final Dio _stubDio;

  @override
  Dio get dio => _stubDio;
}
```

- [ ] **Step 3: Confirm the file analyzes cleanly**

Run:
```bash
flutter analyze test/helpers/test_harness.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add test/helpers/test_harness.dart
git commit -m "test: add StubApiClient to test harness"
```

---

## Task 4: Add the snap helper

**Files:**
- Modify: `test/helpers/test_harness.dart`

- [ ] **Step 1: Add imports**

Add to the import block:

```dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
```

- [ ] **Step 2: Append snap helper**

Append to the file:

```dart
/// Captures the current widget tree to a PNG under `test/screenshots/<name>.png`.
///
/// Walks the render tree to find the first [RenderRepaintBoundary] (CupertinoApp
/// wraps its root in one) and rasterizes it via [RenderRepaintBoundary.toImage].
/// The rasterize + PNG-encode runs inside [WidgetTester.runAsync] so it executes
/// in real time outside the test's fake-async zone. Without this, follow-up
/// pumps hang because dart:ui's image work never completes inside fake-async.
Future<void> snap(WidgetTester tester, String name) async {
  final outDir = Directory('test/screenshots');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  RenderRepaintBoundary? findBoundary(RenderObject node) {
    if (node is RenderRepaintBoundary) return node;
    RenderRepaintBoundary? found;
    node.visitChildren((child) {
      found ??= findBoundary(child);
    });
    return found;
  }

  await tester.runAsync(() async {
    final root = tester.binding.rootElement?.renderObject;
    if (root == null) return;
    final boundary = findBoundary(root);
    if (boundary == null) return;

    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return;
    File('test/screenshots/$name.png')
        .writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
```

- [ ] **Step 3: Confirm the file analyzes cleanly**

Run:
```bash
flutter analyze test/helpers/test_harness.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add test/helpers/test_harness.dart
git commit -m "test: add snap screenshot helper to test harness"
```

---

## Task 5: Add stubConnectivityChannel

**Files:**
- Modify: `test/helpers/test_harness.dart`

- [ ] **Step 1: Add the import**

Add to the import block:

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 2: Append stubConnectivityChannel**

Append to the file:

```dart
/// Stub `connectivity_plus` platform channels so tests don't crash on the
/// `MissingPluginException` thrown when the connectivity provider tries to
/// listen to its event channel.
///
/// Call this from a test's `setUp` (or once in `main()`). It's safe to call
/// repeatedly — the binding's mock handler map just gets overwritten.
void stubConnectivityChannel() {
  const eventChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(eventChannel, (_) async => null);

  const methodChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(methodChannel, (_) async => ['wifi']);
}
```

- [ ] **Step 3: Confirm the file analyzes cleanly**

Run:
```bash
flutter analyze test/helpers/test_harness.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add test/helpers/test_harness.dart
git commit -m "test: add connectivity channel stub to test harness"
```

---

## Task 6: Add bootstrapApp + Harness class

**Files:**
- Modify: `test/helpers/test_harness.dart`

- [ ] **Step 1: Add imports**

Add to the import block:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tts_bandmate/app.dart';
import 'package:tts_bandmate/core/config/router.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
```

- [ ] **Step 2: Append Harness class and bootstrapApp**

Append to the file:

```dart
/// Result of [bootstrapApp]. Hold on to it for the duration of a test so you
/// can read the resulting state (token in [storage], request bodies in
/// [capturedBodies]) after driving the UI.
class Harness {
  Harness({
    required this.widget,
    required this.storage,
    required this.routeStorage,
    required this.capturedBodies,
  });

  /// The fully configured [ProviderScope] wrapping [BandmateApp]. Pass to
  /// `tester.pumpWidget`.
  final Widget widget;

  /// In-memory secure storage. Read it after the test to assert what the app
  /// stored (e.g. auth token).
  final FakeSecureStorage storage;

  /// SharedPreferences-backed route storage. Read it after the test to assert
  /// the saved last-route, if relevant.
  final RouteStorage routeStorage;

  /// Map of request path → list of captured request bodies (parsed JSON).
  /// One list per path, ordered by the order the requests were made.
  final Map<String, List<dynamic>> capturedBodies;
}

/// Build a fully wired [Harness] suitable for `tester.pumpWidget`.
///
/// [handler] is a Dio response handler — given a [RequestOptions], returns a
/// canned [ResponseBody]. The harness will dispatch every HTTP call through
/// this function.
///
/// [initialLocation] is the first route the router lands on. Defaults to
/// `/login` (the same path the production app uses for a logged-out user).
Future<Harness> bootstrapApp({
  required Future<ResponseBody> Function(RequestOptions options) handler,
  String initialLocation = '/login',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final routeStorage = RouteStorage(prefs);
  final storage = FakeSecureStorage();
  final capturedBodies = <String, List<dynamic>>{};

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = StubAdapter(handler, capturedBodies: capturedBodies);
  final apiClient = StubApiClient(storage: storage, dio: dio);

  final widget = ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(apiClient),
      routeStorageProvider.overrideWith((_) async => routeStorage),
      initialLocationProvider.overrideWithValue(initialLocation),
    ],
    child: const BandmateApp(),
  );

  return Harness(
    widget: widget,
    storage: storage,
    routeStorage: routeStorage,
    capturedBodies: capturedBodies,
  );
}
```

- [ ] **Step 3: Confirm the file analyzes cleanly**

Run:
```bash
flutter analyze test/helpers/test_harness.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add test/helpers/test_harness.dart
git commit -m "test: add bootstrapApp + Harness to test harness"
```

---

## Task 7: Smoke test the harness

**Files:**
- Create: `test/helpers/test_harness_smoke_test.dart`

- [ ] **Step 1: Write a smoke test**

Create `test/helpers/test_harness_smoke_test.dart`:

```dart
// Smoke test: confirms the test harness wires up correctly and produces a
// runnable widget tree that lands on /login when no token is present.

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(stubConnectivityChannel);

  testWidgets('bootstrapApp renders /login with no token', (tester) async {
    final harness = await bootstrapApp(
      handler: (options) async => json(200, {}),
    );

    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsOneWidget);
    expect(await harness.storage.readToken(), isNull);
  });

  testWidgets('StubAdapter captures request bodies', (tester) async {
    // This test verifies the capture mechanism in isolation — it builds its
    // own StubAdapter pointing at the harness's capturedBodies map rather
    // than going through the harness's apiClient. That keeps the smoke test
    // short and not coupled to the app's bootstrap behavior.
    final harness = await bootstrapApp(
      handler: (options) async => json(200, {}),
    );

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter(
        (options) async => json(200, {'ok': true}),
        capturedBodies: harness.capturedBodies,
      );

    await dio.post<Map<String, dynamic>>('/echo', data: {'hello': 'world'});

    expect(harness.capturedBodies['/echo'], isNotNull);
    expect(harness.capturedBodies['/echo']!.first, {'hello': 'world'});
  });
}
```

- [ ] **Step 2: Run the smoke test**

Run:
```bash
flutter test test/helpers/test_harness_smoke_test.dart
```

Expected: `+2: All tests passed!`

- [ ] **Step 3: Commit**

```bash
git add test/helpers/test_harness_smoke_test.dart
git commit -m "test: smoke test for shared test harness"
```

---

## Task 8: Migrate login_flow_widget_test.dart to use the harness

**Files:**
- Modify: `test/login_flow_widget_test.dart`

- [ ] **Step 1: Replace the entire file with the harness-based version**

Overwrite `test/login_flow_widget_test.dart` with:

```dart
// Widget-level "integration" test for the login → band-selection → dashboard
// flow.
//
// Uses the shared harness in test/helpers/test_harness.dart. Real router,
// real providers, real screens — only the HTTP layer and a couple of plugin
// channels are stubbed.
//
// Run with:
//   flutter test test/login_flow_widget_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(stubConnectivityChannel);

  testWidgets(
    'login → single band auto-selects → leaves login screen',
    (tester) async {
      final harness = await bootstrapApp(
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileToken)) {
            return json(200, {
              'token': 'fake-token-xyz',
              'user': {
                'id': 1,
                'name': 'Eddie',
                'email': 'eddie@example.com',
              },
              'bands': [
                {'id': 10, 'name': 'The Rocking Eds', 'is_owner': true},
              ],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileMe)) {
            return json(200, {
              'user': {
                'id': 1,
                'name': 'Eddie',
                'email': 'eddie@example.com',
              },
              'bands': [
                {'id': 10, 'name': 'The Rocking Eds', 'is_owner': true},
              ],
            });
          }
          return json(200, {'data': []});
        },
      );

      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
      await snap(tester, '01_login_empty');

      await tester.enterText(
          find.byType(CupertinoTextField).at(0), 'eddie@example.com');
      await tester.enterText(
          find.byType(CupertinoTextField).at(1), 'password123');
      await tester.pump();
      await snap(tester, '02_login_filled');

      await tester.tap(find.text('Sign In'));
      // Bounded pump — destination dashboard screen has streams that don't
      // settle, so pumpAndSettle would hang.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await harness.storage.readToken(), 'fake-token-xyz');
      expect(find.text('Sign In'), findsNothing);

      await snap(tester, '03_after_signin');
    },
  );
}
```

- [ ] **Step 2: Delete the old screenshots so we know they get regenerated**

Run:
```bash
rm -f test/screenshots/01_login_empty.png test/screenshots/02_login_filled.png test/screenshots/03_after_signin.png
```

- [ ] **Step 3: Run the migrated test**

Run:
```bash
flutter test test/login_flow_widget_test.dart
```

Expected: `+1: All tests passed!`

- [ ] **Step 4: Verify all three screenshots were regenerated**

Run:
```bash
ls test/screenshots/
```

Expected output (in any order):
```
01_login_empty.png
02_login_filled.png
03_after_signin.png
```

- [ ] **Step 5: Confirm static analysis is clean**

Run:
```bash
flutter analyze test/
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add test/login_flow_widget_test.dart test/screenshots/
git commit -m "test: migrate login flow test to shared harness"
```

---

## Task 9: Test 1 — signup → solo → dashboard

**Files:**
- Create: `test/onboarding_flows_widget_test.dart`

- [ ] **Step 1: Write the test**

Create `test/onboarding_flows_widget_test.dart`:

```dart
// Widget-level E2E tests for the post-signup onboarding branches: solo,
// create-band (skip / with invites), and join-via-QR.
//
// Each test starts with no token and ends on /dashboard, with a screenshot
// of the final state under test/screenshots/.
//
// Run with:
//   flutter test test/onboarding_flows_widget_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(stubConnectivityChannel);

  group('onboarding flows', () {
    testWidgets('signup → go solo → dashboard', (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 10,
        'name': 'Eddie',
        'is_owner': true,
      };

      final harness = await bootstrapApp(
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileRegister)) {
            return json(200, {
              'token': 'tok',
              'user': user,
              'bands': <Map<String, dynamic>>[],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileBandsSolo)) {
            return json(200, {
              'bands': [band],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileMe)) {
            return json(200, {
              'user': user,
              'bands': [band],
            });
          }
          return json(200, {'data': []});
        },
      );

      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      // /login → tap "Sign up" → /signup
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      // Fill signup: name, email, password, confirm.
      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(0), 'Eddie Mullins');
      await tester.enterText(fields.at(1), 'eddie@example.com');
      await tester.enterText(fields.at(2), 'password123');
      await tester.enterText(fields.at(3), 'password123');
      await tester.pump();

      // Submit. After register completes, router redirects to /bands
      // because bands list is empty.
      await tester.tap(find.text('Create Account'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Path-selection screen heading.
      expect(find.text('How would you like to use Bandmate?'), findsOneWidget);

      // Tap Go Solo card. After /bands/solo and /me complete, single-band
      // auto-select kicks in and router lands on /dashboard.
      await tester.tap(find.text('Go Solo'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Sign In'), findsNothing);
      expect(
          find.text('How would you like to use Bandmate?'), findsNothing);

      await snap(tester, 'solo_01_dashboard');
    });
  });
}
```

- [ ] **Step 2: Run the test**

Run:
```bash
flutter test test/onboarding_flows_widget_test.dart
```

Expected: `+1: All tests passed!`

- [ ] **Step 3: Verify the screenshot was generated**

Run:
```bash
ls test/screenshots/solo_01_dashboard.png
```

Expected: file exists.

- [ ] **Step 4: Confirm analyze is clean**

Run:
```bash
flutter analyze test/
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add test/onboarding_flows_widget_test.dart test/screenshots/solo_01_dashboard.png
git commit -m "test: E2E for signup → go solo → dashboard"
```

---

## Task 10: Test 2 — signup → create band (skip invites) → dashboard

**Files:**
- Modify: `test/onboarding_flows_widget_test.dart`

- [ ] **Step 1: Append the test inside the existing group**

Inside the `group('onboarding flows', () { ... })` block, after the solo test, add:

```dart
    testWidgets('signup → create band (skip invites) → dashboard',
        (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 11,
        'name': 'The Eds',
        'is_owner': true,
      };

      final harness = await bootstrapApp(
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileRegister)) {
            return json(200, {
              'token': 'tok',
              'user': user,
              'bands': <Map<String, dynamic>>[],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileCreateBand)) {
            return json(200, {'band': band});
          }
          if (path.endsWith(ApiEndpoints.mobileMe)) {
            return json(200, {
              'user': user,
              'bands': [band],
            });
          }
          return json(200, {'data': []});
        },
      );

      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      // /login → /signup
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      // Fill and submit signup.
      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(0), 'Eddie Mullins');
      await tester.enterText(fields.at(1), 'eddie@example.com');
      await tester.enterText(fields.at(2), 'password123');
      await tester.enterText(fields.at(3), 'password123');
      await tester.pump();
      await tester.tap(find.text('Create Account'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // /bands → tap "Create a Band" → /bands/create
      await tester.tap(find.text('Create a Band'));
      await tester.pumpAndSettle();

      // Step 1: type band name, tap Next.
      expect(find.text('What\'s your band called?'), findsOneWidget);
      await tester.enterText(
          find.byType(CupertinoTextField).first, 'The Eds');
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Step 2: skip invites.
      expect(find.text('Invite your bandmates'), findsOneWidget);
      await tester.tap(find.text('Skip for now'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Skip for now'), findsNothing);

      await snap(tester, 'create_skip_01_dashboard');
    });
```

- [ ] **Step 2: Run the test (whole file)**

Run:
```bash
flutter test test/onboarding_flows_widget_test.dart
```

Expected: `+2: All tests passed!`

- [ ] **Step 3: Verify the screenshot**

Run:
```bash
ls test/screenshots/create_skip_01_dashboard.png
```

Expected: file exists.

- [ ] **Step 4: Commit**

```bash
git add test/onboarding_flows_widget_test.dart test/screenshots/create_skip_01_dashboard.png
git commit -m "test: E2E for signup → create band (skip invites) → dashboard"
```

---

## Task 11: Test 3 — signup → create band (with invites) → dashboard

**Files:**
- Modify: `test/onboarding_flows_widget_test.dart`

- [ ] **Step 1: Append the test inside the existing group**

Inside the same group, after the skip-invites test, add:

```dart
    testWidgets('signup → create band (with invites) → dashboard',
        (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 11,
        'name': 'The Eds',
        'is_owner': true,
      };

      final harness = await bootstrapApp(
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileRegister)) {
            return json(200, {
              'token': 'tok',
              'user': user,
              'bands': <Map<String, dynamic>>[],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileCreateBand)) {
            return json(200, {'band': band});
          }
          if (path.endsWith(ApiEndpoints.mobileBandInvite(11))) {
            return json(200, <String, dynamic>{});
          }
          if (path.endsWith(ApiEndpoints.mobileMe)) {
            return json(200, {
              'user': user,
              'bands': [band],
            });
          }
          return json(200, {'data': []});
        },
      );

      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(0), 'Eddie Mullins');
      await tester.enterText(fields.at(1), 'eddie@example.com');
      await tester.enterText(fields.at(2), 'password123');
      await tester.enterText(fields.at(3), 'password123');
      await tester.pump();
      await tester.tap(find.text('Create Account'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.tap(find.text('Create a Band'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(CupertinoTextField).first, 'The Eds');
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Step 2: type an invitee email and tap the + button.
      await tester.enterText(
          find.byType(CupertinoTextField).first, 'bandmate@example.com');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.add_circled_solid));
      await tester.pump();

      // The chip should now appear with the email.
      expect(find.text('bandmate@example.com'), findsOneWidget);

      // Submit.
      await tester.tap(find.text('Done'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Assert the captured invite request body.
      final invitePath = ApiEndpoints.mobileBandInvite(11);
      final inviteBodies = harness.capturedBodies[invitePath];
      expect(inviteBodies, isNotNull,
          reason: 'Expected at least one POST to $invitePath');
      expect(inviteBodies!.first, {
        'emails': ['bandmate@example.com']
      });

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Done'), findsNothing);

      await snap(tester, 'create_invite_01_dashboard');
    });
```

- [ ] **Step 2: Run the file**

Run:
```bash
flutter test test/onboarding_flows_widget_test.dart
```

Expected: `+3: All tests passed!`

- [ ] **Step 3: Verify the screenshot**

Run:
```bash
ls test/screenshots/create_invite_01_dashboard.png
```

Expected: file exists.

- [ ] **Step 4: Commit**

```bash
git add test/onboarding_flows_widget_test.dart test/screenshots/create_invite_01_dashboard.png
git commit -m "test: E2E for signup → create band (with invites) → dashboard"
```

---

## Task 12: Test 4 — signup → join via QR → dashboard

This test is the most platform-channel-heavy. The `mobile_scanner` package uses both a method channel (`dev.steenbakker.mobile_scanner/scanner/method`) and an event channel (`dev.steenbakker.mobile_scanner/scanner/event`). On non-mobile platforms its barcode parser refuses to parse, so we also need to override `defaultTargetPlatform` to `iOS` for the duration of the test.

**Files:**
- Modify: `test/onboarding_flows_widget_test.dart`

- [ ] **Step 1: Add a top-level helper for stubbing mobile_scanner**

At the top level of `test/onboarding_flows_widget_test.dart` (above `void main()`), add:

```dart
// Constants & helpers for stubbing mobile_scanner platform channels. The
// package uses an EventChannel for barcode events; we register a mock stream
// handler so we can synthesize a barcode detection event from the test.

const _scannerMethodChannelName =
    'dev.steenbakker.mobile_scanner/scanner/method';
const _scannerEventChannelName =
    'dev.steenbakker.mobile_scanner/scanner/event';

/// Stub the mobile_scanner method channel: respond to permission, start, and
/// teardown methods so the [MobileScanner] widget can mount.
void _stubScannerMethodChannel() {
  const channel = MethodChannel(_scannerMethodChannelName);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'state':
        return 1; // authorized
      case 'request':
        return true;
      case 'start':
        return {
          'textureId': 0,
          'numberOfCameras': 1,
          'currentTorchState': -1,
          'size': {'width': 1080.0, 'height': 1920.0},
        };
      case 'stop':
      case 'pause':
      case 'toggleTorch':
      case 'setScale':
      case 'resetScale':
      case 'updateScanWindow':
      case 'setInvertImage':
        return null;
      default:
        return null;
    }
  });
}

/// Send a barcode-detected event through the mobile_scanner event channel.
/// Call after the [MobileScanner] widget has mounted and subscribed.
Future<void> _emitScannerBarcode(WidgetTester tester, String code) async {
  final encoded =
      const StandardMethodCodec().encodeSuccessEnvelope({
    'name': 'barcode',
    'data': [
      {
        'rawValue': code,
        'format': -1, // BarcodeFormat.unknown – the screen ignores format
        'corners': <Map<String, double>>[],
      },
    ],
  });

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _scannerEventChannelName,
    encoded,
    (_) {},
  );
  await tester.pump();
}
```

Add the necessary imports at the top of the file (alongside the existing ones):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
```

- [ ] **Step 2: Append the QR test inside the group**

Inside the same group, after the with-invites test, add:

```dart
    testWidgets('signup → join via QR → dashboard', (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 12,
        'name': 'The Eds',
        'is_owner': false,
      };

      // mobile_scanner only parses barcode events on Android/iOS/macOS.
      // Override the platform for the duration of this test so the parser
      // doesn't throw on Linux.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      _stubScannerMethodChannel();

      final harness = await bootstrapApp(
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileRegister)) {
            return json(200, {
              'token': 'tok',
              'user': user,
              'bands': <Map<String, dynamic>>[],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileBandsJoin)) {
            return json(200, {
              'bands': [band],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileMe)) {
            return json(200, {
              'user': user,
              'bands': [band],
            });
          }
          return json(200, {'data': []});
        },
      );

      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(0), 'Eddie Mullins');
      await tester.enterText(fields.at(1), 'eddie@example.com');
      await tester.enterText(fields.at(2), 'password123');
      await tester.enterText(fields.at(3), 'password123');
      await tester.pump();
      await tester.tap(find.text('Create Account'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // /bands → "Join a Band" → /bands/join
      await tester.tap(find.text('Join a Band'));
      await tester.pumpAndSettle();

      // /bands/join → tap "Scan QR Code" → scanner mounts.
      await tester.tap(find.text('Scan QR Code'));
      // Pump enough frames for the MobileScanner widget to subscribe to its
      // event channel. We don't pumpAndSettle because the scanner has
      // continuous frames that never quiesce.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Synthesize a barcode detection — the screen's onDetect calls
      // _joinWithKey with the rawValue.
      await _emitScannerBarcode(tester, 'ABC123');

      // Pump for the join request → refreshBands → /me → router redirect.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final joinBodies =
          harness.capturedBodies[ApiEndpoints.mobileBandsJoin];
      expect(joinBodies, isNotNull,
          reason: 'Expected at least one POST to mobileBandsJoin');
      expect(joinBodies!.first, {'key': 'ABC123'});

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Scan QR Code'), findsNothing);

      await snap(tester, 'join_qr_01_dashboard');
    });
```

- [ ] **Step 3: Run the file**

Run:
```bash
flutter test test/onboarding_flows_widget_test.dart
```

Expected: `+4: All tests passed!`

If the QR test fails with `MissingPluginException` on a method we didn't stub: read the error to identify the missing method name, add a case for it to `_stubScannerMethodChannel`, and re-run.

If the QR test fails because the synthesized event isn't received by the widget: increase the pre-emit pump count (the scanner needs more frames to subscribe), or check that `_scannerEventChannelName` matches the actual channel name in `mobile_scanner-6.0.11/lib/src/method_channel/mobile_scanner_method_channel.dart`.

- [ ] **Step 4: Verify the screenshot**

Run:
```bash
ls test/screenshots/join_qr_01_dashboard.png
```

Expected: file exists.

- [ ] **Step 5: Commit**

```bash
git add test/onboarding_flows_widget_test.dart test/screenshots/join_qr_01_dashboard.png
git commit -m "test: E2E for signup → join via QR → dashboard"
```

---

## Task 13: Final acceptance

- [ ] **Step 1: Run the full test directory**

Run:
```bash
flutter test test/
```

Expected: all tests pass — at minimum the existing `auth_provider_test.dart`, the migrated `login_flow_widget_test.dart`, the harness smoke test, and the four new onboarding tests.

- [ ] **Step 2: Confirm no analyze regressions**

Run:
```bash
flutter analyze
```

Expected: `No issues found!` (or only the same pre-existing warnings as before this plan started, if any).

- [ ] **Step 3: Confirm all expected screenshots exist**

Run:
```bash
ls test/screenshots/
```

Expected (in some order):
```
01_login_empty.png
02_login_filled.png
03_after_signin.png
create_invite_01_dashboard.png
create_skip_01_dashboard.png
join_qr_01_dashboard.png
solo_01_dashboard.png
```

- [ ] **Step 4: Visually inspect each new screenshot**

Open each of the four new dashboard PNGs in your image viewer (or use the Read tool if working in Claude Code) and confirm they look like a dashboard — calendar visible, bottom nav with first tab selected, no error overlays. Text glyphs appear as box-shapes (tofu) — this is expected since `flutter test` runs with `--use-test-fonts`.

- [ ] **Step 5: Done — no commit needed for this task; everything is already committed**

---

## Notes for the executor

- **Bounded `pump` instead of `pumpAndSettle`:** Whenever the test ends up on a screen with continuous animations or open streams (dashboard, scanner, calendar), `pumpAndSettle` will time out. The pattern is `for (var i = 0; i < N; i++) await tester.pump(const Duration(milliseconds: 50));`. Use `pumpAndSettle` only on quiet screens (login, signup, path-selection, create-band steps).
- **Tofu text:** `flutter test` runs the engine with `--use-test-fonts --disable-asset-fonts`. Real fonts aren't loaded, so visible text in screenshots renders as box glyphs. Layout, colors, widget tree, and active-tab indicators are still meaningful.
- **The `snap` helper is fake-async-safe:** It wraps `boundary.toImage()` in `tester.runAsync` so the rasterize completes outside the fake-async zone. Don't remove that wrapping or follow-up pumps will hang.
- **Connectivity stub:** `setUp(stubConnectivityChannel)` is required for every test that pumps `BandmateApp`. The connectivity provider listens to its event channel during app boot and throws `MissingPluginException` without it.
- **`mobile_scanner` channel names** are taken from `~/.pub-cache/hosted/pub.dev/mobile_scanner-6.0.11/lib/src/method_channel/mobile_scanner_method_channel.dart`. If `mobile_scanner` is upgraded, re-verify the channel names and the barcode event format (`{name: 'barcode', data: [{rawValue: ..., format: ..., corners: ...}]}`).
