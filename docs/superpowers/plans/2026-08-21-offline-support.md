# Offline Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app usable offline for viewing previously loaded data — cached homepage/events/setlist/bookings, no data ever discarded by a failed refresh, friendly offline errors, auto-revalidation on reconnect.

**Architecture:** Generalize the stale-while-revalidate pattern already proven in `bookings_window_provider.dart`: raw API JSON cached in SharedPreferences (`ApiCacheStorage`), painted instantly in `build()`, revalidated in a deferred background fetch, kept on any network error. A `SwrSupport` mixin carries the pattern into simple notifiers; `DashboardNotifier` hand-wires the same flow (its state is windowed). Connectivity is seeded and the offline→online edge triggers revalidation.

**Tech Stack:** Flutter/Dart, Riverpod v3 (classic providers, no codegen), Dio, shared_preferences, connectivity_plus. **No new dependencies.**

**Spec:** `docs/superpowers/specs/2026-08-21-offline-support-design.md`

## Global Constraints

- No new pub dependencies.
- Cache **raw API JSON** only — models have no `toJson()`; cached payloads re-enter through the same `fromJson` path as live responses.
- Cache keys are band-scoped: `api_cache_v1:<bandId>:<logical-name>`.
- No `dart:io` imports in shared/provider code (the app builds for web). Detect socket errors via `DioExceptionType` and `error.toString()`.
- Never discard on-screen data: a refresh/revalidate failure with data present keeps state silently.
- Read-only offline: no mutation queue. Writes keep failing; they now render the friendly offline message.
- Run tests with `flutter test <file>`; lint with `flutter analyze`. Both must be clean at every commit.
- Commit after each task with the trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- One deliberate deviation from the spec (flagged for review): **band switch does NOT clear the cache.** Keys are band-scoped so there is no cross-band leakage, and keeping other bands' caches lets a user switch bands while offline. `clearAll()` runs on logout (different-user protection).

---

### Task 1: `ApiCacheStorage` — shared raw-JSON cache

**Files:**
- Create: `lib/shared/cache/api_cache_storage.dart`
- Modify: `lib/main.dart` (~line 141 construct, ~line 175 override)
- Test: `test/shared/cache/api_cache_storage_test.dart`

**Interfaces:**
- Consumes: `SharedPreferences` (pre-resolved in `main()`).
- Produces (later tasks rely on these exact signatures):
  - `class CachedEntry { final DateTime savedAt; final Map<String, dynamic> payload; }`
  - `class ApiCacheStorage { CachedEntry? read(String key); void write(String key, Map<String, dynamic> payload); void remove(String key); void clearAll(); }`
  - `final apiCacheStorageProvider = Provider<ApiCacheStorage>(...)` — throws unless overridden in `main()`/tests.

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/cache/api_cache_storage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
  });

  test('read returns null when nothing cached', () {
    expect(storage.read('7:dashboard'), isNull);
  });

  test('write/read round-trips payload and stamps savedAt', () {
    final before = DateTime.now();
    storage.write('7:dashboard', {'events': [{'id': 1}], 'upcoming_charts': []});
    final entry = storage.read('7:dashboard');
    expect(entry, isNotNull);
    expect(entry!.payload['events'], [{'id': 1}]);
    expect(entry.savedAt.isBefore(before.subtract(const Duration(seconds: 5))), isFalse);
  });

  test('malformed blob is cleared and returns null', () async {
    SharedPreferences.setMockInitialValues({'api_cache_v1:7:dashboard': 'not json'});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    expect(storage.read('7:dashboard'), isNull);
    expect(storage.read('7:dashboard'), isNull); // stays null, no throw
  });

  test('remove drops one entry, clearAll drops every api_cache entry only', () async {
    SharedPreferences.setMockInitialValues({'unrelated_key': 'keep'});
    final prefs = await SharedPreferences.getInstance();
    storage = ApiCacheStorage(prefs);
    storage.write('7:dashboard', {'a': 1});
    storage.write('7:event:abc', {'b': 2});
    storage.write('9:dashboard', {'c': 3});

    storage.remove('7:event:abc');
    expect(storage.read('7:event:abc'), isNull);
    expect(storage.read('7:dashboard'), isNotNull);

    storage.clearAll();
    expect(storage.read('7:dashboard'), isNull);
    expect(storage.read('9:dashboard'), isNull);
    expect(prefs.getString('unrelated_key'), 'keep');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/cache/api_cache_storage_test.dart`
Expected: FAIL — `api_cache_storage.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/shared/cache/api_cache_storage.dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One cached API payload plus the moment it was stored.
class CachedEntry {
  const CachedEntry({required this.savedAt, required this.payload});

  final DateTime savedAt;
  final Map<String, dynamic> payload;
}

/// `SharedPreferences`-backed store of raw API JSON payloads for offline
/// viewing. Generalizes `BookingsCacheStorage`: raw JSON is stored (models
/// have no `toJson`) so cached data re-enters through the same
/// `Model.fromJson` path as a live response.
///
/// Callers pass band-scoped keys (`<bandId>:<logical-name>`); the storage
/// prefixes them with a versioned namespace so [clearAll] can drop every
/// cache entry without touching unrelated preferences.
class ApiCacheStorage {
  ApiCacheStorage(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'api_cache_v1:';

  /// Returns the cached entry, or null if absent or unparseable. A malformed
  /// blob is cleared so subsequent reads don't keep failing.
  CachedEntry? read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedEntry(
        savedAt: DateTime.fromMillisecondsSinceEpoch(
            (decoded['savedAt'] as num).toInt()),
        payload: decoded['payload'] as Map<String, dynamic>,
      );
    } catch (_) {
      _prefs.remove('$_prefix$key');
      return null;
    }
  }

  void write(String key, Map<String, dynamic> payload) {
    _prefs.setString(
      '$_prefix$key',
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'payload': payload,
      }),
    );
  }

  /// Drops one entry — used after a local mutation so the next rebuild takes
  /// the cold path instead of warm-painting pre-mutation data.
  void remove(String key) {
    _prefs.remove('$_prefix$key');
  }

  /// Drops every cached payload. Called on logout so a different user
  /// signing in on this device never sees the previous user's data.
  void clearAll() {
    for (final k
        in _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      _prefs.remove(k);
    }
  }
}

/// Resolved at startup in `main.dart` (mirrors `bookingsCacheStorageProvider`).
/// The override supplies a pre-resolved instance so synchronous `read()`
/// works inside provider `build()` methods.
final apiCacheStorageProvider = Provider<ApiCacheStorage>((ref) {
  throw UnimplementedError(
    'apiCacheStorageProvider must be overridden in main()',
  );
});
```

- [ ] **Step 4: Wire into `main.dart`**

Add import `'shared/cache/api_cache_storage.dart'`. Next to `final bookingsCacheStorage = BookingsCacheStorage(prefs);` (~line 141) add:

```dart
  final apiCacheStorage = ApiCacheStorage(prefs);
```

In the `ProviderScope(overrides: [...])` list (~line 175), after the `bookingsCacheStorageProvider` line add:

```dart
          apiCacheStorageProvider.overrideWithValue(apiCacheStorage),
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/shared/cache/api_cache_storage_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/shared/cache/api_cache_storage.dart lib/main.dart test/shared/cache/api_cache_storage_test.dart
git commit -m "feat: shared ApiCacheStorage for offline raw-JSON caching"
```

---

### Task 2: `swr.dart` — offline error helpers + `SwrSupport` mixin

**Files:**
- Create: `lib/shared/cache/swr.dart`
- Test: `test/shared/cache/swr_test.dart`

**Interfaces:**
- Consumes: `apiCacheStorageProvider` (Task 1), `connectivityProvider`, `selectedBandProvider`.
- Produces (later tasks rely on these exact signatures):
  - `class OfflineException implements Exception { const OfflineException(); }`
  - `const String kOfflineMessage = "You're offline. Check your connection and try again.";`
  - `bool isOfflineError(Object e)`
  - `mixin SwrSupport<T> on AsyncNotifier<T>` with:
    - `Future<T> swrBuild({required String name, required T Function(Map<String, dynamic> payload) decode, required Future<({T value, Map<String, dynamic> raw})> Function() fetch})`
    - `Future<void> swrRevalidate({required String name, required Future<({T value, Map<String, dynamic> raw})> Function() fetch})`

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/cache/swr_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

/// Selected-band stub: band 7, resolved synchronously.
class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

typedef _Fetch = Future<({List<String> value, Map<String, dynamic> raw})>
    Function();

/// Minimal concrete notifier exercising the mixin.
class _TestNotifier extends AsyncNotifier<List<String>>
    with SwrSupport<List<String>> {
  _TestNotifier(this.fetcher);
  final _Fetch fetcher;

  static List<String> decode(Map<String, dynamic> payload) =>
      (payload['items'] as List<dynamic>).cast<String>();

  @override
  Future<List<String>> build() =>
      swrBuild(name: 'test', decode: decode, fetch: fetcher);

  Future<void> refresh() => swrRevalidate(name: 'test', fetch: fetcher);
}

DioException _connectionError() => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    );

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;

  Future<ProviderContainer> makeContainer({
    required _Fetch fetch,
    bool online = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWith((ref) => Stream.value(online)),
    ]);
    addTearDown(container.dispose);
    // Let the connectivity stream emit so `.value` is meaningful.
    await container.read(connectivityProvider.future);
    await container.read(selectedBandProvider.future);
    return container;
  }

  late _Fetch fetcher;
  final provider = AsyncNotifierProvider<_TestNotifier, List<String>>(
    () => _TestNotifier(() => fetcher()),
  );

  group('isOfflineError', () {
    test('true for connection-type DioExceptions and OfflineException', () {
      expect(isOfflineError(_connectionError()), isTrue);
      expect(isOfflineError(const OfflineException()), isTrue);
      expect(
        isOfflineError(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionTimeout,
        )),
        isTrue,
      );
    });

    test('false for HTTP-response errors and plain exceptions', () {
      expect(
        isOfflineError(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: '/x'), statusCode: 500),
        )),
        isFalse,
      );
      expect(isOfflineError(Exception('nope')), isFalse);
    });
  });

  group('swrBuild', () {
    test('cold path fetches, caches, and returns fresh data', () async {
      fetcher = () async => (value: ['fresh'], raw: {'items': ['fresh']});
      final container = await makeContainer(fetch: () => fetcher());
      final result = await container.read(provider.future);
      expect(result, ['fresh']);
      expect(storage.read('7:test')!.payload['items'], ['fresh']);
    });

    test('warm path paints cache instantly then revalidates', () async {
      var calls = 0;
      fetcher = () async {
        calls++;
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final container = await makeContainer(fetch: () => fetcher());
      storage.write('7:test', {'items': ['cached']});

      final first = await container.read(provider.future);
      expect(first, ['cached']); // instant paint, no network await

      await _flushMicrotasks();
      expect(calls, 1);
      expect(container.read(provider).value, ['fresh']);
      expect(storage.read('7:test')!.payload['items'], ['fresh']);
    });

    test('warm path keeps cached data when revalidate hits a connection error',
        () async {
      fetcher = () async => throw _connectionError();
      final container = await makeContainer(fetch: () => fetcher());
      storage.write('7:test', {'items': ['cached']});

      final first = await container.read(provider.future);
      expect(first, ['cached']);
      await _flushMicrotasks();
      final state = container.read(provider);
      expect(state.hasError, isFalse);
      expect(state.value, ['cached']);
    });

    test('cold path offline with empty cache throws OfflineException',
        () async {
      fetcher = () async => (value: ['fresh'], raw: {'items': ['fresh']});
      final container =
          await makeContainer(fetch: () => fetcher(), online: false);
      await expectLater(
          container.read(provider.future), throwsA(isA<OfflineException>()));
    });
  });

  group('swrRevalidate', () {
    test('never emits loading and keeps data on failure', () async {
      var shouldThrow = false;
      fetcher = () async {
        if (shouldThrow) throw _connectionError();
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final container = await makeContainer(fetch: () => fetcher());
      await container.read(provider.future);

      final states = <AsyncValue<List<String>>>[];
      container.listen(provider, (_, next) => states.add(next));

      shouldThrow = true;
      await container.read(provider.notifier).refresh();

      expect(states.whereType<AsyncLoading<List<String>>>(), isEmpty);
      expect(container.read(provider).value, ['fresh']);
    });

    test('surfaces error when there is no data on screen', () async {
      fetcher = () async => throw _connectionError();
      final container =
          await makeContainer(fetch: () => fetcher(), online: false);
      await expectLater(
          container.read(provider.future), throwsA(isA<OfflineException>()));
      // Still offline, still no data: refresh keeps the error state.
      await container.read(provider.notifier).refresh();
      expect(container.read(provider).hasError, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/cache/swr_test.dart`
Expected: FAIL — `swr.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/shared/cache/swr.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_provider.dart';
import '../providers/selected_band_provider.dart';
import 'api_cache_storage.dart';

/// User-facing copy for offline failures. Shared by `ErrorView` and the
/// setlist screen so the message stays consistent app-wide.
const String kOfflineMessage =
    "You're offline. Check your connection and try again.";

/// Thrown when a fetch is skipped (or would be pointless) because the device
/// is offline and no cached data exists to fall back on.
class OfflineException implements Exception {
  const OfflineException();

  @override
  String toString() => kOfflineMessage;
}

/// True for errors caused by missing connectivity rather than the server.
///
/// Web-safe: no `dart:io` import — a wrapped `SocketException` is detected
/// via `toString()` because the concrete type only exists on IO platforms.
bool isOfflineError(Object e) {
  if (e is OfflineException) return true;
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      default:
        return e.error?.toString().contains('SocketException') ?? false;
    }
  }
  return false;
}

/// Stale-while-revalidate support for `AsyncNotifier`s, generalizing the
/// pattern proven in `BookingsWindowNotifier`:
///
/// - `build()` paints instantly from the disk cache when possible and
///   revalidates in a deferred background fetch;
/// - revalidation NEVER discards on-screen data — failures with data present
///   are silent;
/// - when offline, network attempts are skipped entirely (no timeout wait).
///
/// Notifiers with windowed/merged state (dashboard, bookings window) hand-roll
/// the same flow instead; this mixin serves the simple fetch-and-render ones.
mixin SwrSupport<T> on AsyncNotifier<T> {
  /// Band-scoped cache key, or null when no band is selected (skip caching).
  String? _swrKey(String name) {
    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) return null;
    return '$bandId:$name';
  }

  /// Latest known connectivity. `null` (stream not yet emitted) is treated
  /// as online so we never wrongly skip a fetch.
  bool get _isOffline => ref.read(connectivityProvider).value == false;

  /// SWR build flow. [decode] parses a cached payload; [fetch] returns the
  /// fresh parsed value plus the raw response JSON to cache. Both must decode
  /// through the SAME `fromJson` path so cached and live data are identical.
  Future<T> swrBuild({
    required String name,
    required T Function(Map<String, dynamic> payload) decode,
    required Future<({T value, Map<String, dynamic> raw})> Function() fetch,
  }) async {
    final key = _swrKey(name);
    final cached = key == null ? null : ref.read(apiCacheStorageProvider).read(key);
    if (cached != null) {
      // Defer the background refresh until after the framework commits this
      // build's returned value — otherwise revalidate's `state = …` lands
      // first and is immediately overwritten by build's own result.
      // ignore: unawaited_futures
      Future<void>(() => swrRevalidate(name: name, fetch: fetch));
      return decode(cached.payload);
    }

    // Cold path. Offline with nothing cached: fail fast with a friendly
    // error instead of waiting out the connect timeout.
    if (_isOffline) throw const OfflineException();
    final result = await fetch();
    if (key != null) ref.read(apiCacheStorageProvider).write(key, result.raw);
    return result.value;
  }

  /// Background revalidation, also used as the non-destructive `refresh()`.
  /// Keeps existing data on ANY failure; only surfaces an error when there is
  /// nothing on screen. Never emits `AsyncLoading`.
  Future<void> swrRevalidate({
    required String name,
    required Future<({T value, Map<String, dynamic> raw})> Function() fetch,
  }) async {
    if (_isOffline && state.hasValue) return; // keep data, skip the attempt
    try {
      if (_isOffline) throw const OfflineException();
      final result = await fetch();
      if (!ref.mounted) return;
      final key = _swrKey(name);
      if (key != null) {
        ref.read(apiCacheStorageProvider).write(key, result.raw);
      }
      state = AsyncData(result.value);
    } catch (e, st) {
      if (!ref.mounted) return;
      if (state.hasValue) return; // never discard on-screen data
      state = AsyncError(e, st);
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/cache/swr_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze
git add lib/shared/cache/swr.dart test/shared/cache/swr_test.dart
git commit -m "feat: SwrSupport mixin + offline error helpers"
```

---

### Task 3: Connectivity seeding + friendly offline errors

**Files:**
- Modify: `lib/shared/providers/connectivity_provider.dart` (whole file, 9 lines)
- Modify: `lib/shared/widgets/error_view.dart:14-26` (`friendlyMessage`)
- Test: `test/shared/widgets/error_view_test.dart` (new)

**Interfaces:**
- Consumes: `kOfflineMessage`, `isOfflineError` from Task 2.
- Produces: `connectivityProvider` unchanged in type (`StreamProvider<bool>`) but now emits an initial seeded value; `ErrorView.friendlyMessage` maps offline errors to `kOfflineMessage`.

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/widgets/error_view_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';

void main() {
  test('connection-type DioExceptions map to the offline message', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/api/mobile/dashboard'),
      type: DioExceptionType.connectionError,
    );
    expect(ErrorView.friendlyMessage(e), kOfflineMessage);
  });

  test('OfflineException maps to the offline message', () {
    expect(
        ErrorView.friendlyMessage(const OfflineException()), kOfflineMessage);
  });

  test('server message from a response body still wins for HTTP errors', () {
    final e = DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 422,
        data: {'message': 'Name is required.'},
      ),
    );
    expect(ErrorView.friendlyMessage(e), 'Name is required.');
  });

  test('non-network errors fall back to toString', () {
    expect(ErrorView.friendlyMessage(StateError('boom')),
        contains('boom'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/error_view_test.dart`
Expected: FAIL — connection error currently returns the raw `DioException` toString.

- [ ] **Step 3: Update `ErrorView.friendlyMessage`**

In `lib/shared/widgets/error_view.dart` add `import '../cache/swr.dart';` and replace the method:

```dart
  /// Extracts a human-readable message from an error.
  /// Offline/connection failures map to [kOfflineMessage]. For [DioException]
  /// with a response, the body's `message` field wins. Falls back to
  /// [e.toString()] for all other error types.
  static String friendlyMessage(Object e) {
    if (isOfflineError(e)) return kOfflineMessage;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final msg = data['message'];
        if (msg is String && msg.isNotEmpty) return msg;
      }
    }
    return e.toString();
  }
```

- [ ] **Step 4: Seed the connectivity stream**

Replace the body of `lib/shared/providers/connectivity_provider.dart`:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the current connectivity state. `true` = online, `false` = offline.
///
/// Seeded with an initial `checkConnectivity()` so `.value` is correct from
/// startup — `onConnectivityChanged` alone only emits on CHANGE, which left
/// the state `null` (treated as online) until the first transition.
///
/// Known limitation: `connectivity_plus` reports link presence, not
/// reachability — a captive portal reads as online. The SWR layer's
/// keep-data-on-error policy covers that case.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
});
```

(No unit test — the plugin's platform channel isn't mockable without wrapper scaffolding that YAGNI forbids; behavior is covered by the on-device checklist in Task 9. Tests that override `connectivityProvider` with `Stream.value(...)` are unaffected.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/shared/widgets/error_view_test.dart && flutter test test/shared/cache/`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/shared/providers/connectivity_provider.dart lib/shared/widgets/error_view.dart test/shared/widgets/error_view_test.dart
git commit -m "feat: seed connectivity state; friendly offline error copy"
```

---

### Task 4: Events — SWR list + event detail conversion

**Files:**
- Modify: `lib/features/events/data/events_repository.dart:17-47`
- Modify: `lib/features/events/providers/events_provider.dart` (BandEventsNotifier + eventDetailProvider)
- Test: `test/features/events/providers/events_provider_offline_test.dart` (new)

**Interfaces:**
- Consumes: `SwrSupport`, `apiCacheStorageProvider`, `OfflineException` (Tasks 1-2).
- Produces:
  - `EventsRepository.parseBandEvents(Map<String, dynamic> data) → List<EventSummary>` (static)
  - `EventsRepository.parseEventDetail(Map<String, dynamic> data) → EventDetail` (static)
  - `getBandEventsRaw(int bandId, {String? from, String? to}) → Future<({List<EventSummary> parsed, Map<String, dynamic> raw})>`
  - `getEventDetailRaw(String key) → Future<({EventDetail parsed, Map<String, dynamic> raw})>`
  - `eventDetailProvider` becomes `AsyncNotifierProvider.family<EventDetailNotifier, EventDetail, String>` — same watch/read/invalidate/.future surface for all existing call sites (`event_detail_screen.dart`, `roster_sheet.dart`, `band_realtime_provider.dart`, `lodging_edit_screen.dart`, `cache_invalidator.dart`).
  - Cache names: `events:<bandId>:<from ?? ''>:<to ?? ''>` and `event:<eventKey>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/events/providers/events_provider_offline_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

Map<String, dynamic> _eventJson(int id, String title) => {
      'id': id,
      'key': 'evt-$id',
      'title': title,
      'date': '2026-09-01',
    };

class _StubEventsRepo implements EventsRepository {
  _StubEventsRepo({this.listResponse, this.detailResponse, this.error});

  Map<String, dynamic>? listResponse;
  Map<String, dynamic>? detailResponse;
  Object? error;
  int listCalls = 0;
  int detailCalls = 0;

  @override
  Future<({List<EventSummary> parsed, Map<String, dynamic> raw})>
      getBandEventsRaw(int bandId, {String? from, String? to}) async {
    listCalls++;
    if (error != null) throw error!;
    final data = listResponse!;
    return (parsed: EventsRepository.parseBandEvents(data), raw: data);
  }

  @override
  Future<({EventDetail parsed, Map<String, dynamic> raw})> getEventDetailRaw(
      String key) async {
    detailCalls++;
    if (error != null) throw error!;
    final data = detailResponse!;
    return (parsed: EventsRepository.parseEventDetail(data), raw: data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _connectionError() => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    );

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;
  late _StubEventsRepo repo;

  Future<ProviderContainer> makeContainer({bool online = true}) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWith((ref) => Stream.value(online)),
      eventsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(connectivityProvider.future);
    await container.read(selectedBandProvider.future);
    return container;
  }

  const params = BandEventsParams(bandId: 7);

  test('events list: cold fetch populates the cache', () async {
    repo = _StubEventsRepo(listResponse: {
      'events': [_eventJson(1, 'Gig A')],
    });
    final container = await makeContainer();
    final events = await container.read(bandEventsProvider(params).future);
    expect(events.single.title, 'Gig A');
    expect(storage.read('7:events:7::'), isNotNull);
  });

  test('events list: warm paint from cache, then revalidates', () async {
    repo = _StubEventsRepo(listResponse: {
      'events': [_eventJson(2, 'Fresh gig')],
    });
    final container = await makeContainer();
    storage.write('7:events:7::', {
      'events': [_eventJson(1, 'Cached gig')],
    });

    final first = await container.read(bandEventsProvider(params).future);
    expect(first.single.title, 'Cached gig');
    await _flushMicrotasks();
    expect(
        container.read(bandEventsProvider(params)).value!.single.title,
        'Fresh gig');
  });

  test('events list: refresh keeps data on connection error, no loading',
      () async {
    repo = _StubEventsRepo(listResponse: {
      'events': [_eventJson(1, 'Gig A')],
    });
    final container = await makeContainer();
    await container.read(bandEventsProvider(params).future);

    final states = <AsyncValue<List<EventSummary>>>[];
    container.listen(bandEventsProvider(params), (_, next) => states.add(next));

    repo.error = _connectionError();
    await container.read(bandEventsProvider(params).notifier).refresh();

    expect(states.whereType<AsyncLoading<List<EventSummary>>>(), isEmpty);
    expect(container.read(bandEventsProvider(params)).value!.single.title,
        'Gig A');
  });

  test('event detail: warm paint from cache when offline', () async {
    repo = _StubEventsRepo(error: _connectionError());
    final container = await makeContainer(online: false);
    storage.write('7:event:evt-1', {
      'event': _eventJson(1, 'Cached gig'),
    });

    final detail = await container.read(eventDetailProvider('evt-1').future);
    expect(detail.title, 'Cached gig');
  });

  test('event detail: offline with empty cache throws OfflineException',
      () async {
    repo = _StubEventsRepo(error: _connectionError());
    final container = await makeContainer(online: false);
    await expectLater(container.read(eventDetailProvider('evt-9').future),
        throwsA(isA<OfflineException>()));
  });
}
```

Note: if `EventSummary.fromJson`/`EventDetail.fromJson` need more required keys than `_eventJson` provides, extend `_eventJson` with the minimal extra keys (check `lib/features/events/data/models/`) rather than changing the models.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/events/providers/events_provider_offline_test.dart`
Expected: FAIL — `getBandEventsRaw`/`getEventDetailRaw` don't exist.

- [ ] **Step 3: Add raw repo methods**

In `lib/features/events/data/events_repository.dart`, replace `getBandEvents` and `getEventDetail` with:

```dart
  /// Parses the events-list payload. Shared by live fetches and the offline
  /// cache so both go through identical decoding.
  static List<EventSummary> parseBandEvents(Map<String, dynamic> data) {
    final rawList = data['events'] as List<dynamic>? ?? [];
    return rawList
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();
  }

  /// Parses the event-detail payload (same sharing rationale).
  static EventDetail parseEventDetail(Map<String, dynamic> data) =>
      EventDetail.fromJson(data['event'] as Map<String, dynamic>);

  /// Fetches the list of events for [bandId].
  ///
  /// Optional [from] and [to] are ISO date strings used to filter the range,
  /// e.g. "2026-04-01".
  Future<List<EventSummary>> getBandEvents(
    int bandId, {
    String? from,
    String? to,
  }) async =>
      (await getBandEventsRaw(bandId, from: from, to: to)).parsed;

  /// Like [getBandEvents] but also returns the raw response JSON so callers
  /// can persist it verbatim (the models have no `toJson`).
  Future<({List<EventSummary> parsed, Map<String, dynamic> raw})>
      getBandEventsRaw(
    int bandId, {
    String? from,
    String? to,
  }) async {
    final queryParams = <String, String>{};
    if (from != null) queryParams['from'] = from;
    if (to != null) queryParams['to'] = to;

    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandEvents(bandId),
      queryParameters: queryParams.isEmpty ? null : queryParams,
    );

    final data = response.data!;
    return (parsed: parseBandEvents(data), raw: data);
  }

  /// Fetches the full detail for the event identified by [key].
  Future<EventDetail> getEventDetail(String key) async =>
      (await getEventDetailRaw(key)).parsed;

  /// Like [getEventDetail] but also returns the raw response JSON.
  Future<({EventDetail parsed, Map<String, dynamic> raw})> getEventDetailRaw(
      String key) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileEventDetail(key),
    );

    final data = response.data!;
    return (parsed: parseEventDetail(data), raw: data);
  }
```

(Note: `parseBandEvents` uses `?? []` where the old inline code cast directly — same tolerance the dashboard parser already has.)

- [ ] **Step 4: Wire SWR into the providers**

In `lib/features/events/providers/events_provider.dart`, add `import '../../../shared/cache/swr.dart';` and replace `BandEventsNotifier` and `eventDetailProvider`:

```dart
class BandEventsNotifier extends AsyncNotifier<List<EventSummary>>
    with SwrSupport<List<EventSummary>> {
  BandEventsNotifier(this._params);
  final BandEventsParams _params;

  String get _cacheName =>
      'events:${_params.bandId}:${_params.from ?? ''}:${_params.to ?? ''}';

  Future<({List<EventSummary> value, Map<String, dynamic> raw})>
      _fetch() async {
    final repo = ref.read(eventsRepositoryProvider);
    final result = await repo.getBandEventsRaw(_params.bandId,
        from: _params.from, to: _params.to);
    return (value: result.parsed, raw: result.raw);
  }

  @override
  Future<List<EventSummary>> build() {
    // Watch (not read) so a band/client change rebuilds this provider.
    ref.watch(eventsRepositoryProvider);
    return swrBuild(
      name: _cacheName,
      decode: EventsRepository.parseBandEvents,
      fetch: _fetch,
    );
  }

  Future<void> refresh() => swrRevalidate(name: _cacheName, fetch: _fetch);
}

final bandEventsProvider = AsyncNotifierProvider.family<
    BandEventsNotifier, List<EventSummary>, BandEventsParams>(
  (arg) => BandEventsNotifier(arg),
);

class EventDetailNotifier extends AsyncNotifier<EventDetail>
    with SwrSupport<EventDetail> {
  EventDetailNotifier(this._eventKey);
  final String _eventKey;

  Future<({EventDetail value, Map<String, dynamic> raw})> _fetch() async {
    final result =
        await ref.read(eventsRepositoryProvider).getEventDetailRaw(_eventKey);
    return (value: result.parsed, raw: result.raw);
  }

  @override
  Future<EventDetail> build() {
    ref.watch(eventsRepositoryProvider);
    return swrBuild(
      name: 'event:$_eventKey',
      decode: EventsRepository.parseEventDetail,
      fetch: _fetch,
    );
  }
}

final eventDetailProvider =
    AsyncNotifierProvider.family<EventDetailNotifier, EventDetail, String>(
  (key) => EventDetailNotifier(key),
);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/events/providers/events_provider_offline_test.dart && flutter test test/features/events/`
Expected: PASS (including pre-existing events tests — if an existing test stubbed `getBandEvents`, it now must stub `getBandEventsRaw` instead; update those stubs, not the production code).

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/features/events test/features/events
git commit -m "feat: offline SWR caching for events list and event detail"
```

---

### Task 5: Dashboard — warm paint + non-destructive refresh

**Files:**
- Modify: `lib/features/dashboard/data/dashboard_repository.dart:15-37`
- Modify: `lib/features/dashboard/providers/dashboard_provider.dart:176-221` (`build`, `refresh`)
- Test: `test/features/dashboard/providers/dashboard_provider_offline_test.dart` (new)

**Interfaces:**
- Consumes: `apiCacheStorageProvider`, `OfflineException`, `connectivityProvider` (read directly — `DashboardNotifier`'s windowed state doesn't fit the mixin, mirroring how `BookingsWindowNotifier` hand-rolls).
- Produces:
  - `DashboardRepository.parseDashboard(Map<String, dynamic> data) → ({List<EventSummary> events, List<UpcomingChart> upcomingCharts})` (static)
  - `getDashboardRaw({String? to}) → Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts, Map<String, dynamic> raw})>`
  - Cache name: `dashboard` (key `<bandId>:dashboard`).
  - `DashboardNotifier.refresh()` keeps its `Future<void> refresh()` signature — every existing caller (`dashboard_screen.dart`, `cache_invalidator.dart`, `band_realtime_provider.dart`) works unchanged, now non-destructively.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/dashboard/providers/dashboard_provider_offline_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

Map<String, dynamic> _dashboardJson(String title) => {
      'events': [
        {'id': 1, 'key': 'evt-1', 'title': title, 'date': '2026-09-01'},
      ],
      'upcoming_charts': <Map<String, dynamic>>[],
    };

class _StubDashboardRepo implements DashboardRepository {
  _StubDashboardRepo({this.response, this.error});

  Map<String, dynamic>? response;
  Object? error;
  int calls = 0;

  @override
  Future<
      ({
        List<EventSummary> events,
        List<UpcomingChart> upcomingCharts,
        Map<String, dynamic> raw
      })> getDashboardRaw({String? to}) async {
    calls++;
    if (error != null) throw error!;
    final data = response!;
    final parsed = DashboardRepository.parseDashboard(data);
    return (
      events: parsed.events,
      upcomingCharts: parsed.upcomingCharts,
      raw: data
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _connectionError() => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    );

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;
  late _StubDashboardRepo repo;

  Future<ProviderContainer> makeContainer({bool online = true}) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWith((ref) => Stream.value(online)),
      dashboardRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(connectivityProvider.future);
    await container.read(selectedBandProvider.future);
    return container;
  }

  test('cold fetch populates the cache', () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Live gig'));
    final container = await makeContainer();
    final state = await container.read(dashboardProvider.future);
    expect(state.events.single.title, 'Live gig');
    expect(storage.read('7:dashboard'), isNotNull);
  });

  test('warm paint from cache, then background revalidate', () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Fresh gig'));
    final container = await makeContainer();
    storage.write('7:dashboard', _dashboardJson('Cached gig'));

    final first = await container.read(dashboardProvider.future);
    expect(first.events.single.title, 'Cached gig');
    await _flushMicrotasks();
    expect(container.read(dashboardProvider).value!.events.single.title,
        'Fresh gig');
  });

  test('refresh keeps on-screen data on connection error, never loading',
      () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Live gig'));
    final container = await makeContainer();
    await container.read(dashboardProvider.future);

    final states = <AsyncValue<DashboardState>>[];
    container.listen(dashboardProvider, (_, next) => states.add(next));

    repo.error = _connectionError();
    await container.read(dashboardProvider.notifier).refresh();

    expect(states.whereType<AsyncLoading<DashboardState>>(), isEmpty);
    final after = container.read(dashboardProvider);
    expect(after.hasError, isFalse);
    expect(after.value!.events.single.title, 'Live gig');
  });

  test('offline refresh with data present skips the network entirely',
      () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Cached gig'));
    final container = await makeContainer(online: false);
    storage.write('7:dashboard', _dashboardJson('Cached gig'));
    await container.read(dashboardProvider.future);
    await _flushMicrotasks();
    final callsBefore = repo.calls;

    await container.read(dashboardProvider.notifier).refresh();
    expect(repo.calls, callsBefore); // no attempt made
    expect(container.read(dashboardProvider).value!.events, isNotEmpty);
  });

  test('offline cold start with empty cache throws OfflineException',
      () async {
    repo = _StubDashboardRepo(error: _connectionError());
    final container = await makeContainer(online: false);
    await expectLater(container.read(dashboardProvider.future),
        throwsA(isA<OfflineException>()));
    expect(repo.calls, 0); // failed fast, no timeout wait
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/dashboard/providers/dashboard_provider_offline_test.dart`
Expected: FAIL — `getDashboardRaw`/`parseDashboard` don't exist.

- [ ] **Step 3: Add the raw repo method**

In `lib/features/dashboard/data/dashboard_repository.dart`, replace `getDashboard` with:

```dart
  /// Parses the dashboard payload. Shared by live fetches and the offline
  /// cache so both go through identical decoding.
  static ({List<EventSummary> events, List<UpcomingChart> upcomingCharts})
      parseDashboard(Map<String, dynamic> data) {
    final rawEvents = data['events'] as List<dynamic>? ?? [];
    final events = rawEvents
        .cast<Map<String, dynamic>>()
        .map(EventSummary.fromJson)
        .toList();

    final rawCharts = data['upcoming_charts'] as List<dynamic>? ?? [];
    final upcomingCharts = rawCharts
        .cast<Map<String, dynamic>>()
        .map(UpcomingChart.fromJson)
        .toList();

    return (events: events, upcomingCharts: upcomingCharts);
  }

  /// Fetches the dashboard payload — upcoming events and charts.
  /// [to] (yyyy-MM-dd, exclusive) bounds the forward window; events beyond it
  /// are fetched lazily via [loadNewerEvents].
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async {
    final result = await getDashboardRaw(to: to);
    return (events: result.events, upcomingCharts: result.upcomingCharts);
  }

  /// Like [getDashboard] but also returns the raw response JSON so callers
  /// can persist it verbatim (the models have no `toJson`).
  Future<
      ({
        List<EventSummary> events,
        List<UpcomingChart> upcomingCharts,
        Map<String, dynamic> raw
      })> getDashboardRaw({String? to}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileDashboard,
      queryParameters: {if (to != null) 'to': to},
    );

    final data = response.data!;
    final parsed = parseDashboard(data);
    return (
      events: parsed.events,
      upcomingCharts: parsed.upcomingCharts,
      raw: data
    );
  }
```

- [ ] **Step 4: Rewrite `build()` and `refresh()` in `DashboardNotifier`**

Add imports to `lib/features/dashboard/providers/dashboard_provider.dart`:

```dart
import '../../../shared/cache/api_cache_storage.dart';
import '../../../shared/cache/swr.dart';
import '../../../shared/providers/connectivity_provider.dart';
```

Inside `DashboardNotifier`, add helpers and replace `build`/`refresh` (leave `loadOlder`, `_loadNewer`, `ensureMonthLoaded`, `_ensureMonthLoadedBackward` untouched):

```dart
  static const String _cacheName = 'dashboard';

  String? _cacheKey() {
    final bandId = ref.read(selectedBandProvider).value;
    return bandId == null ? null : '$bandId:$_cacheName';
  }

  bool get _isOffline => ref.read(connectivityProvider).value == false;

  @override
  Future<DashboardState> build() async {
    final initialFrom = _dateOnly(
      DateTime.now().subtract(const Duration(days: _initialPastWindowDays)),
    );
    final initialTo = _initialTo();

    // Wait for band selection to resolve before fetching — avoids a missing
    // X-Band-ID header on the first request when storage hasn't been read yet.
    final bandId = await ref.watch(selectedBandProvider.future);
    if (bandId == null) {
      return DashboardState(
        events: const [],
        upcomingCharts: const [],
        loadedFrom: initialFrom,
        loadedTo: initialTo,
      );
    }

    final repo = ref.watch(dashboardRepositoryProvider);
    final cache = ref.read(apiCacheStorageProvider);

    final cached = cache.read('$bandId:$_cacheName');
    if (cached != null) {
      // Instant paint from disk, then refresh in the background. Watermarks
      // are computed fresh from now — the cached events fill whatever slice
      // of the window they cover until revalidation lands.
      final parsed = DashboardRepository.parseDashboard(cached.payload);
      // Defer the background refresh until after the framework commits this
      // build's returned value — otherwise refresh's `state = …` lands first
      // and is immediately overwritten by build's own result.
      // ignore: unawaited_futures
      Future<void>(refresh);
      return DashboardState(
        events: parsed.events,
        upcomingCharts: parsed.upcomingCharts,
        loadedFrom: initialFrom,
        loadedTo: initialTo,
      );
    }

    // Cold path. Offline with nothing cached: fail fast with a friendly
    // error instead of waiting out the connect timeout.
    if (_isOffline) throw const OfflineException();
    final result = await repo.getDashboardRaw(to: _ymd(initialTo));
    cache.write('$bandId:$_cacheName', result.raw);
    return DashboardState(
      events: result.events,
      upcomingCharts: result.upcomingCharts,
      loadedFrom: initialFrom,
      loadedTo: initialTo,
    );
  }

  /// Re-fetches the dashboard from the server, in place. NEVER discards
  /// on-screen data: with data present, a failure is silent and offline skips
  /// the attempt entirely. Only from an empty/error state does it show a
  /// loading spinner (the explicit user retry path).
  Future<void> refresh() async {
    final hadValue = state.hasValue;
    if (!hadValue) state = const AsyncValue.loading();
    try {
      if (_isOffline) {
        if (hadValue) return; // keep data, skip the attempt
        throw const OfflineException();
      }
      final initialTo = _initialTo();
      final repo = ref.read(dashboardRepositoryProvider);
      final result = await repo.getDashboardRaw(to: _ymd(initialTo));
      if (!ref.mounted) return;
      final key = _cacheKey();
      if (key != null) {
        ref.read(apiCacheStorageProvider).write(key, result.raw);
      }
      state = AsyncValue.data(DashboardState(
        events: result.events,
        upcomingCharts: result.upcomingCharts,
        loadedFrom: _dateOnly(
          DateTime.now().subtract(const Duration(days: _initialPastWindowDays)),
        ),
        loadedTo: initialTo,
      ));
    } catch (e, st) {
      if (!ref.mounted) return;
      if (state.hasValue) return; // never discard on-screen data
      state = AsyncValue.error(e, st);
    }
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/dashboard/providers/dashboard_provider_offline_test.dart && flutter test test/features/dashboard/`
Expected: PASS. Pre-existing dashboard tests that asserted refresh's loading-reset behavior (if any) must be updated to the new non-destructive contract; tests stubbing `getDashboard` may need to stub `getDashboardRaw` instead.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/features/dashboard test/features/dashboard
git commit -m "feat: dashboard offline warm-paint + non-destructive refresh"
```

---

### Task 6: Booking detail — SWR conversion

**Files:**
- Modify: `lib/features/bookings/data/bookings_repository.dart:113-120`
- Modify: `lib/features/bookings/providers/bookings_provider.dart:51-57`
- Test: `test/features/bookings/providers/booking_detail_offline_test.dart` (new)

**Interfaces:**
- Consumes: `SwrSupport` (Task 2).
- Produces:
  - `BookingsRepository.parseBookingDetail(Map<String, dynamic> data) → BookingDetail` (static)
  - `getBookingDetailRaw(int bandId, int bookingId) → Future<({BookingDetail parsed, Map<String, dynamic> raw})>`
  - `bookingDetailProvider` becomes `AsyncNotifierProvider.family<BookingDetailNotifier, BookingDetail, ({int bandId, int bookingId})>` — same surface for all call sites (`booking_detail_screen.dart`, `booking_contract_screen.dart`, `booking_payments_screen.dart`, `booking_contacts_screen.dart`, `contract_editor_provider.dart` `.future`, `band_realtime_provider.dart`, `lodging_edit_screen.dart`, `cache_invalidator.dart`).
  - Cache name: `booking:<bookingId>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/bookings/providers/booking_detail_offline_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

Map<String, dynamic> _bookingJson(String name) => {
      'booking': {
        'id': 42,
        'name': name,
        'date': '2026-09-01',
        'contacts': <Map<String, dynamic>>[],
        'events': <Map<String, dynamic>>[],
      },
    };

class _StubBookingsRepo implements BookingsRepository {
  _StubBookingsRepo({this.response, this.error});

  Map<String, dynamic>? response;
  Object? error;

  @override
  Future<({BookingDetail parsed, Map<String, dynamic> raw})>
      getBookingDetailRaw(int bandId, int bookingId) async {
    if (error != null) throw error!;
    final data = response!;
    return (parsed: BookingsRepository.parseBookingDetail(data), raw: data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;
  late _StubBookingsRepo repo;

  Future<ProviderContainer> makeContainer({bool online = true}) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWith((ref) => Stream.value(online)),
      bookingsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(connectivityProvider.future);
    await container.read(selectedBandProvider.future);
    return container;
  }

  const args = (bandId: 7, bookingId: 42);

  test('cold fetch populates the cache', () async {
    repo = _StubBookingsRepo(response: _bookingJson('Wedding'));
    final container = await makeContainer();
    final detail = await container.read(bookingDetailProvider(args).future);
    expect(detail.name, 'Wedding');
    expect(storage.read('7:booking:42'), isNotNull);
  });

  test('warm paint from cache when offline', () async {
    repo = _StubBookingsRepo(
        error: DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    ));
    final container = await makeContainer(online: false);
    storage.write('7:booking:42', _bookingJson('Cached wedding'));

    final detail = await container.read(bookingDetailProvider(args).future);
    expect(detail.name, 'Cached wedding');
  });

  test('offline with empty cache throws OfflineException', () async {
    repo = _StubBookingsRepo();
    final container = await makeContainer(online: false);
    await expectLater(container.read(bookingDetailProvider(args).future),
        throwsA(isA<OfflineException>()));
  });
}
```

Note: adjust `_bookingJson` minimal keys to whatever `BookingDetail.fromJson` requires (check `lib/features/bookings/data/models/booking_detail.dart`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/bookings/providers/booking_detail_offline_test.dart`
Expected: FAIL — `getBookingDetailRaw` doesn't exist.

- [ ] **Step 3: Add the raw repo method**

In `lib/features/bookings/data/bookings_repository.dart`, replace `getBookingDetail` (lines 113-120) with:

```dart
  /// Parses the booking-detail payload. Shared by live fetches and the
  /// offline cache so both go through identical decoding.
  static BookingDetail parseBookingDetail(Map<String, dynamic> data) =>
      BookingDetail.fromJson(data['booking'] as Map<String, dynamic>);

  Future<BookingDetail> getBookingDetail(int bandId, int bookingId) async =>
      (await getBookingDetailRaw(bandId, bookingId)).parsed;

  /// Like [getBookingDetail] but also returns the raw response JSON so
  /// callers can persist it verbatim (the models have no `toJson`).
  Future<({BookingDetail parsed, Map<String, dynamic> raw})>
      getBookingDetailRaw(int bandId, int bookingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBookingDetail(bandId, bookingId),
    );

    final data = response.data!;
    return (parsed: parseBookingDetail(data), raw: data);
  }
```

- [ ] **Step 4: Convert the provider**

In `lib/features/bookings/providers/bookings_provider.dart`, add `import '../../../shared/cache/swr.dart';` and replace `bookingDetailProvider` (lines 53-57):

```dart
class BookingDetailNotifier extends AsyncNotifier<BookingDetail>
    with SwrSupport<BookingDetail> {
  BookingDetailNotifier(this._args);
  final ({int bandId, int bookingId}) _args;

  Future<({BookingDetail value, Map<String, dynamic> raw})> _fetch() async {
    final result = await ref
        .read(bookingsRepositoryProvider)
        .getBookingDetailRaw(_args.bandId, _args.bookingId);
    return (value: result.parsed, raw: result.raw);
  }

  @override
  Future<BookingDetail> build() {
    ref.watch(bookingsRepositoryProvider);
    return swrBuild(
      name: 'booking:${_args.bookingId}',
      decode: BookingsRepository.parseBookingDetail,
      fetch: _fetch,
    );
  }
}

final bookingDetailProvider = AsyncNotifierProvider.family<
    BookingDetailNotifier, BookingDetail, ({int bandId, int bookingId})>(
  (args) => BookingDetailNotifier(args),
);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/bookings/`
Expected: PASS (update any existing stub of `getBookingDetail` to stub `getBookingDetailRaw` instead).

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/features/bookings test/features/bookings
git commit -m "feat: offline SWR caching for booking detail"
```

---

### Task 7: Setlist — cached read-only view offline

**Files:**
- Modify: `lib/features/setlist/data/setlist_repository.dart:13-31`
- Modify: `lib/features/setlist/providers/live_session_provider.dart:74-96` (`load()`)
- Test: `test/features/setlist/live_session_offline_test.dart` (new; `test/features/setlist/` dir doesn't exist yet — create it)

**Interfaces:**
- Consumes: `apiCacheStorageProvider`, `isOfflineError`, `kOfflineMessage` (Tasks 1-2), `selectedBandProvider`.
- Produces:
  - `SetlistRepository.parseSession(Map<String, dynamic> data) → ({LiveSession? session, List<BandSong> songs, bool isCaptain, bool canWrite, int currentUserId})` (static)
  - `getSessionRaw(String eventKey)` returning the same record plus `Map<String, dynamic> raw`.
  - Cache name: `setlist_session:<eventKey>`.
  - Offline behavior: cached song list/session painted with `isCaptain: false, canWrite: false` (controls are server-driven, view-only offline); no Pusher connect attempt.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/setlist/live_session_offline_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/features/setlist/data/setlist_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> sessionJson() => {
        'session': null,
        'songs': [
          {'id': 1, 'title': 'Song A'},
          {'id': 2, 'title': 'Song B'},
        ],
        'is_captain': true,
        'can_write': true,
        'current_user_id': 5,
      };

  test('parseSession decodes the same shape getSession used to', () {
    final parsed = SetlistRepository.parseSession(sessionJson());
    expect(parsed.songs, hasLength(2));
    expect(parsed.songs.first.title, 'Song A');
    expect(parsed.isCaptain, isTrue);
    expect(parsed.canWrite, isTrue);
    expect(parsed.currentUserId, 5);
    expect(parsed.session, isNull);
  });

  test('cached payload round-trips through ApiCacheStorage + parseSession',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = ApiCacheStorage(await SharedPreferences.getInstance());
    storage.write('7:setlist_session:evt-1', sessionJson());
    final entry = storage.read('7:setlist_session:evt-1');
    final parsed = SetlistRepository.parseSession(entry!.payload);
    expect(parsed.songs, hasLength(2));
  });
}
```

(The notifier's offline fallback is hard to drive end-to-end in a unit test because `LiveSessionNotifier` constructs its repository from `apiClientProvider` internally; the parse/round-trip layer is what the fallback depends on, and the fallback branch itself is exercised in the Task 9 on-device checklist. If `BandSong.fromJson` needs more keys, extend `sessionJson()` minimally — check `lib/features/setlist/data/models/band_song.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/setlist/live_session_offline_test.dart`
Expected: FAIL — `parseSession` doesn't exist.

- [ ] **Step 3: Split the repo method**

In `lib/features/setlist/data/setlist_repository.dart`, replace `getSession` with:

```dart
  /// Parses the session payload. Shared by live fetches and the offline
  /// cache so both go through identical decoding.
  static ({
    LiveSession? session,
    List<BandSong> songs,
    bool isCaptain,
    bool canWrite,
    int currentUserId
  }) parseSession(Map<String, dynamic> data) {
    final sessionJson = data['session'] as Map<String, dynamic>?;
    final songs = (data['songs'] as List<dynamic>? ?? [])
        .map((e) => BandSong.fromJson(e as Map<String, dynamic>))
        .toList();

    return (
      session: sessionJson != null ? LiveSession.fromJson(sessionJson) : null,
      songs: songs,
      isCaptain: data['is_captain'] as bool? ?? false,
      canWrite: data['can_write'] as bool? ?? false,
      currentUserId: data['current_user_id'] as int,
    );
  }

  Future<({LiveSession? session, List<BandSong> songs, bool isCaptain, bool canWrite, int currentUserId})>
      getSession(String eventKey) async {
    final result = await getSessionRaw(eventKey);
    return (
      session: result.session,
      songs: result.songs,
      isCaptain: result.isCaptain,
      canWrite: result.canWrite,
      currentUserId: result.currentUserId,
    );
  }

  /// Like [getSession] but also returns the raw response JSON so callers can
  /// persist it verbatim (the models have no `toJson`).
  Future<
      ({
        LiveSession? session,
        List<BandSong> songs,
        bool isCaptain,
        bool canWrite,
        int currentUserId,
        Map<String, dynamic> raw
      })> getSessionRaw(String eventKey) async {
    final resp = await _dio.get('/api/mobile/setlist/events/$eventKey/session');
    final data = resp.data as Map<String, dynamic>;
    final parsed = parseSession(data);
    return (
      session: parsed.session,
      songs: parsed.songs,
      isCaptain: parsed.isCaptain,
      canWrite: parsed.canWrite,
      currentUserId: parsed.currentUserId,
      raw: data
    );
  }
```

- [ ] **Step 4: Offline fallback in `load()`**

In `lib/features/setlist/providers/live_session_provider.dart` add imports:

```dart
import '../../../shared/cache/api_cache_storage.dart';
import '../../../shared/cache/swr.dart';
import '../../../shared/providers/selected_band_provider.dart';
```

Replace `load()`:

```dart
  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: () => null);
    final bandId = ref.read(selectedBandProvider).value;
    final cacheKey =
        bandId == null ? null : '$bandId:setlist_session:$_eventKey';
    final cache = ref.read(apiCacheStorageProvider);
    try {
      final result = await _repository.getSessionRaw(_eventKey);
      if (cacheKey != null) cache.write(cacheKey, result.raw);
      state = state.copyWith(
        session: () => result.session,
        songs: result.songs,
        isCaptain: result.isCaptain,
        canWrite: result.canWrite,
        currentUserId: result.currentUserId,
        isLoading: false,
      );

      if (result.session != null) {
        await _connectPusher(result.session!.id);
      }
    } catch (e) {
      // Offline fallback: paint the cached song list read-only so the band
      // can still see the set with no signal. Controls stay disabled
      // (isCaptain/canWrite false) — session actions are server-driven, and
      // no Pusher connect is attempted.
      final cached = cacheKey == null ? null : cache.read(cacheKey);
      if (cached != null && isOfflineError(e)) {
        final parsed = SetlistRepository.parseSession(cached.payload);
        state = state.copyWith(
          session: () => parsed.session,
          songs: parsed.songs,
          isCaptain: false,
          canWrite: false,
          currentUserId: parsed.currentUserId,
          isLoading: false,
          error: () => null,
        );
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: () => isOfflineError(e) ? kOfflineMessage : e.toString(),
      );
    }
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/setlist/live_session_offline_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/features/setlist test/features/setlist
git commit -m "feat: cached read-only setlist view when offline"
```

---

### Task 8: Reconnect revalidation, logout wipe, stale-flash removal

**Files:**
- Modify: `lib/shared/cache/cache_invalidator.dart`
- Modify: `lib/shared/widgets/app_scaffold.dart:134-142` (offline→online listener)
- Modify: `lib/features/auth/providers/auth_provider.dart:244+` (`logout`)
- Test: `test/shared/cache/cache_invalidator_test.dart` (extend)

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `CacheInvalidator.onReconnected()` — revalidates all wired providers on the offline→online edge.
  - Mutation paths (`onEventChanged`, `onBookingChanged`, `onBookingDeleted`, `onBookingDetailChanged`, `onBookingEventsChanged`) drop the matching `ApiCacheStorage` entry BEFORE invalidating, so a post-mutation rebuild takes the cold path instead of warm-painting pre-mutation data (same reasoning as the existing `bookingsCacheStorageProvider.clear()` line).
  - `logout()` calls `ApiCacheStorage.clearAll()`.

- [ ] **Step 1: Write the failing test**

Extend `test/shared/cache/cache_invalidator_test.dart` (follow its existing container/fake setup — read the file first) with:

```dart
  test('onEventChanged drops the event cache entry before invalidating', () async {
    // Arrange: storage overridden in the container (see file's setup), band 7.
    storage.write('7:event:evt-1', {'event': {'id': 1}});
    container.read(cacheInvalidatorProvider).onEventChanged(eventKey: 'evt-1');
    expect(storage.read('7:event:evt-1'), isNull);
  });

  test('onBookingDetailChanged drops the booking cache entry', () async {
    storage.write('7:booking:42', {'booking': {'id': 42}});
    container.read(cacheInvalidatorProvider).onBookingDetailChanged(
        bandId: 7, bookingId: 42);
    expect(storage.read('7:booking:42'), isNull);
  });
```

The existing test file's overrides must gain `apiCacheStorageProvider.overrideWithValue(storage)` (plus `selectedBandProvider` band-7 fake and a `Stream.value(true)` connectivity override if not already present).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/cache/cache_invalidator_test.dart`
Expected: New tests FAIL (cache entries survive).

- [ ] **Step 3: Update `CacheInvalidator`**

In `lib/shared/cache/cache_invalidator.dart` add imports:

```dart
import '../../shared/providers/selected_band_provider.dart';
import 'api_cache_storage.dart';
```

Add the private helper and `onReconnected`, and thread `_removeCache` into the mutation methods:

```dart
  /// Drops one band-scoped `ApiCacheStorage` entry so the next provider
  /// rebuild takes the cold path instead of warm-painting pre-mutation data
  /// (same reasoning as the `bookingsCacheStorageProvider.clear()` below).
  void _removeCache(String name) {
    final bandId = _ref.read(selectedBandProvider).value;
    if (bandId == null) return;
    _ref.read(apiCacheStorageProvider).remove('$bandId:$name');
  }

  /// Call on the offline→online edge (see `app_scaffold.dart`). Revalidates
  /// the offline-cached providers so stale data refreshes without user
  /// action. Every target warm-paints from cache during rebuild, so this
  /// never blanks a screen.
  void onReconnected() {
    _ref.read(dashboardProvider.notifier).refresh();
    _ref.invalidate(bandEventsProvider);
    _ref.invalidate(eventDetailProvider);
    _ref.invalidate(bookingDetailProvider);
    _ref.invalidate(bookingsWindowProvider);
  }
```

Then add `_removeCache` calls next to each detail invalidation:
- `onBookingChanged`: inside the `if (bookingId != null)` block, before the invalidate: `_removeCache('booking:$bookingId');`
- `onBookingDeleted`: before the detail invalidate: `_removeCache('booking:$bookingId');`
- `onBookingDetailChanged`: at the top: `_removeCache('booking:$bookingId');`
- `onBookingEventsChanged`: at the top: `_removeCache('booking:$bookingId');`
- `onEventChanged`: at the top: `_removeCache('event:$eventKey');`

- [ ] **Step 4: Hook the offline→online edge and logout**

`lib/shared/widgets/app_scaffold.dart` — add `import '../cache/cache_invalidator.dart';` and inside the existing listener's `if (!wasOnline && isOnline) {` block (line ~137), first line:

```dart
        ref.read(cacheInvalidatorProvider).onReconnected();
```

`lib/features/auth/providers/auth_provider.dart` — add `import '../../../shared/cache/api_cache_storage.dart';` and in `logout()`, next to the existing `bookingsCacheStorageProvider` clear:

```dart
    // Drop the offline API cache so a different user signing in on this
    // device never sees the previous user's data.
    try {
      ref.read(apiCacheStorageProvider).clearAll();
    } catch (_) {}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/shared/`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/shared lib/features/auth test/shared
git commit -m "feat: reconnect revalidation, logout cache wipe, post-mutation cache drops"
```

---

### Task 9: Full verification

**Files:** none new.

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: ALL PASS. Fix any straggler (most likely: an old test stubbing a repo method replaced by its `…Raw` variant, or asserting the old loading-reset refresh). Rule: adapt tests to the new contract; never weaken the new offline tests.

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit any test fixes**

```bash
git add -A test
git commit -m "test: adapt existing suites to SWR contracts"
```

(Skip if nothing changed.)

- [ ] **Step 4: On-device verification (manual, via the run-on-device skill)**

1. Warm app + airplane mode: dashboard/events/event detail/booking detail/setlist keep showing data; pull-to-refresh does NOT blank the screen; offline banner shows.
2. Airplane-mode cold start with warm cache: dashboard paints from cache (no 10s spinner).
3. Airplane-mode cold start, logged in, empty cache (fresh install + login while online, force-stop, clear only api_cache via reinstall alternative — or simply first-run): friendly "You're offline…" ErrorView with Retry — no raw DioException text.
4. Disable airplane mode: within a few seconds data revalidates without user action ("Back online" banner fires the edge).
5. Offline write attempt (e.g. edit an event) fails with the friendly offline message.
6. Logout → login as the same user: screens cold-fetch (cache was wiped).

---

## Self-Review Notes

- Spec coverage: cache storage (T1), SWR helper (T2), connectivity seed + error UX (T3), dashboard (T5), events list + detail (T4), booking detail (T6), setlist view (T7), reconnect + logout + never-discard refresh (T5/T8), testing (all + T9). Bookings *list/window* already had SWR pre-spec.
- Deviation from spec (flagged in Global Constraints): no cache clear on band switch — keys are band-scoped; keeping caches enables offline band switching.
- Type consistency: `({T value, Map<String, dynamic> raw})` fetch records in the mixin; repo raw methods return `({X parsed, Map<String, dynamic> raw})` and notifiers adapt `parsed`→`value` in their private `_fetch()`.
