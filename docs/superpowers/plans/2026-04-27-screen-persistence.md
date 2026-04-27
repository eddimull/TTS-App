# Screen Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On cold launch, return the authenticated user to the last route they visited (full path, e.g. `/bookings/42`), provided it was saved within the last 24 hours; clear it on logout.

**Architecture:** A new `RouteStorage` class wraps `SharedPreferences` to persist the last route path and a timestamp. A `LastRouteObserver` (NavigatorObserver) writes the route on every shell navigation event. The existing GoRouter redirect chain gains a final step that reads the stored route and redirects there at startup if valid.

**Tech Stack:** Flutter, Dart, Riverpod v2, GoRouter 17, shared_preferences

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `pubspec.yaml` | Modify | Add `shared_preferences` dependency |
| `lib/core/storage/route_storage.dart` | Create | `RouteStorage` class + `routeStorageProvider` |
| `test/core/storage/route_storage_test.dart` | Create | Unit tests for `RouteStorage` |
| `lib/core/config/router.dart` | Modify | Add `LastRouteObserver`; wire `routeStorageProvider` into `_RouterRefreshNotifier`; add restore step to redirect |
| `lib/features/auth/providers/auth_provider.dart` | Modify | Call `routeStorage.clearLastRoute()` in `logout()` |

---

## Task 1: Add shared_preferences dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, add `shared_preferences: ^2.3.3` under `dependencies` (after `flutter_secure_storage`):

```yaml
  flutter_secure_storage: ^10.0.0
  shared_preferences: ^2.3.3
```

- [ ] **Step 2: Install the package**

```bash
flutter pub get
```

Expected output: `Resolving dependencies... Got dependencies!` (no errors).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add shared_preferences dependency"
```

---

## Task 2: Create RouteStorage

**Files:**
- Create: `lib/core/storage/route_storage.dart`
- Create: `test/core/storage/route_storage_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/core/storage/route_storage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RouteStorage', () {
    Future<RouteStorage> build() async {
      final prefs = await SharedPreferences.getInstance();
      return RouteStorage(prefs);
    }

    test('readLastRoute returns null when nothing stored', () async {
      final storage = await build();
      expect(storage.readLastRoute(), isNull);
    });

    test('readLastRouteTimestamp returns null when nothing stored', () async {
      final storage = await build();
      expect(storage.readLastRouteTimestamp(), isNull);
    });

    test('writeLastRoute persists path and timestamp', () async {
      final storage = await build();
      storage.writeLastRoute('/bookings/42');
      expect(storage.readLastRoute(), '/bookings/42');
      expect(storage.readLastRouteTimestamp(), isNotNull);
    });

    test('writeLastRoute overwrites previous value', () async {
      final storage = await build();
      storage.writeLastRoute('/dashboard');
      storage.writeLastRoute('/library/7');
      expect(storage.readLastRoute(), '/library/7');
    });

    test('clearLastRoute removes path and timestamp', () async {
      final storage = await build();
      storage.writeLastRoute('/bookings/42');
      storage.clearLastRoute();
      expect(storage.readLastRoute(), isNull);
      expect(storage.readLastRouteTimestamp(), isNull);
    });

    test('timestamp is within a few seconds of now', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final storage = await build();
      storage.writeLastRoute('/search');
      final ts = storage.readLastRouteTimestamp()!;
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(ts.isAfter(before), isTrue);
      expect(ts.isBefore(after), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/core/storage/route_storage_test.dart
```

Expected: compilation error — `route_storage.dart` does not exist yet.

- [ ] **Step 3: Implement RouteStorage**

Create `lib/core/storage/route_storage.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Keys {
  static const String lastRoute = 'last_route';
  static const String lastRouteTimestamp = 'last_route_timestamp';
}

class RouteStorage {
  RouteStorage(this._prefs);

  final SharedPreferences _prefs;

  String? readLastRoute() => _prefs.getString(_Keys.lastRoute);

  DateTime? readLastRouteTimestamp() {
    final ms = _prefs.getString(_Keys.lastRouteTimestamp);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.parse(ms));
  }

  void writeLastRoute(String path) {
    _prefs.setString(_Keys.lastRoute, path);
    _prefs.setString(
      _Keys.lastRouteTimestamp,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  void clearLastRoute() {
    _prefs.remove(_Keys.lastRoute);
    _prefs.remove(_Keys.lastRouteTimestamp);
  }
}

final routeStorageProvider = FutureProvider<RouteStorage>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return RouteStorage(prefs);
});
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
flutter test test/core/storage/route_storage_test.dart
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/storage/route_storage.dart test/core/storage/route_storage_test.dart
git commit -m "feat: add RouteStorage for last-route persistence"
```

---

## Task 3: Add LastRouteObserver to the router

**Files:**
- Modify: `lib/core/config/router.dart`

This task adds the `LastRouteObserver` class and wires `routeStorageProvider` into `_RouterRefreshNotifier` so GoRouter re-evaluates once SharedPreferences has loaded.

- [ ] **Step 1: Add the import for RouteStorage at the top of router.dart**

In `lib/core/config/router.dart`, add this import after the existing imports:

```dart
import '../storage/route_storage.dart';
```

- [ ] **Step 2: Add the LastRouteObserver class**

Add this class after the `_DismissKeyboardObserver` class (around line 65 in `router.dart`):

```dart
/// The shell route prefixes that are safe to persist as a last-route.
/// Pre-auth and deep-link-only paths are excluded.
const _kShellPrefixes = [
  '/dashboard',
  '/search',
  '/bookings',
  '/library',
  '/more',
  '/band-settings',
  '/finances',
];

class LastRouteObserver extends NavigatorObserver {
  LastRouteObserver(this._routeStorage);

  final RouteStorage _routeStorage;

  void _save(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null) return;
    if (_kShellPrefixes.any((p) => name.startsWith(p))) {
      _routeStorage.writeLastRoute(name);
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) => _save(route);
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    if (newRoute != null) _save(newRoute);
  }
  @override
  void didPop(Route route, Route? previousRoute) {
    if (previousRoute != null) _save(previousRoute);
  }
}
```

- [ ] **Step 3: Wire routeStorageProvider into _RouterRefreshNotifier**

Replace the existing `_RouterRefreshNotifier` class:

```dart
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    _ref.listen(authProvider, (_, __) => notifyListeners());
    _ref.listen(selectedBandProvider, (_, __) => notifyListeners());
    _ref.listen(routeStorageProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}
```

- [ ] **Step 4: Wire LastRouteObserver into the GoRouter observers list**

In `routerProvider`, the `GoRouter(...)` call has `observers: [_DismissKeyboardObserver()]`. Change it to:

```dart
    final routeStorageAsync = ref.watch(routeStorageProvider);
    final routeStorage = routeStorageAsync.valueOrNull;
```

Add these two lines right after `final notifier = _RouterRefreshNotifier(ref);` and before `return GoRouter(...)`.

Then update the observers list:

```dart
    observers: [
      _DismissKeyboardObserver(),
      if (routeStorage != null) LastRouteObserver(routeStorage),
    ],
```

- [ ] **Step 5: Run analyze to confirm no errors**

```bash
flutter analyze lib/core/config/router.dart
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/core/config/router.dart
git commit -m "feat: add LastRouteObserver to track last visited shell route"
```

---

## Task 4: Add last-route restore to the redirect logic

**Files:**
- Modify: `lib/core/config/router.dart`

This task adds the final step to the redirect chain: after auth + band guards pass, check for a stored route and redirect there if valid.

- [ ] **Step 1: Add the restore step to the redirect function**

In `lib/core/config/router.dart`, find the section at the bottom of the redirect lambda that reads:

```dart
        debugPrint('[Router] all good — no redirect');
      }

      return null;
    },
```

Replace it with:

```dart
        // Restore last route on cold start if within 24 hours.
        final routeStorageAsync = ref.read(routeStorageProvider);
        if (routeStorageAsync.isLoading) {
          debugPrint('[Router] routeStorage still loading — staying put');
          return null;
        }
        final rs = routeStorageAsync.valueOrNull;
        if (rs != null) {
          final lastRoute = rs.readLastRoute();
          final lastTs = rs.readLastRouteTimestamp();
          final isRecent = lastTs != null &&
              DateTime.now().difference(lastTs).inHours < 24;
          final isShellPath = lastRoute != null &&
              _kShellPrefixes.any((p) => lastRoute.startsWith(p));
          if (isRecent && isShellPath && state.matchedLocation != lastRoute) {
            debugPrint('[Router] restoring last route: $lastRoute');
            return lastRoute;
          }
        }

        debugPrint('[Router] all good — no redirect');
      }

      return null;
    },
```

- [ ] **Step 2: Run analyze**

```bash
flutter analyze lib/core/config/router.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/config/router.dart
git commit -m "feat: restore last route on cold start via router redirect"
```

---

## Task 5: Clear last route on logout

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`

- [ ] **Step 1: Add the import for RouteStorage**

In `lib/features/auth/providers/auth_provider.dart`, add this import after the existing imports:

```dart
import '../../../core/storage/route_storage.dart';
```

- [ ] **Step 2: Update logout() to clear the stored route**

Find the `logout()` method. It currently reads:

```dart
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);

    // Best-effort server logout — ignore errors (token may already be invalid).
    try {
      await _repository.logout();
    } catch (_) {}

    await storage.clear();
    state = const AsyncValue.data(AuthUnauthenticated());
  }
```

Replace it with:

```dart
  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);

    // Best-effort server logout — ignore errors (token may already be invalid).
    try {
      await _repository.logout();
    } catch (_) {}

    await storage.clear();

    final routeStorageAsync = await ref.read(routeStorageProvider.future);
    routeStorageAsync.clearLastRoute();

    state = const AsyncValue.data(AuthUnauthenticated());
  }
```

- [ ] **Step 3: Run analyze**

```bash
flutter analyze lib/features/auth/providers/auth_provider.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Run all tests**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart
git commit -m "feat: clear last route on logout"
```

---

## Task 6: Manual smoke test

- [ ] **Step 1: Run the app on Linux desktop**

```bash
flutter run -d linux
```

- [ ] **Step 2: Navigate to a nested route**

Log in, select a band, navigate to a booking detail screen (e.g. tap a booking). The URL in debug output will show something like `/bookings/1/42`.

- [ ] **Step 3: Quit and relaunch**

Press `q` to quit the app, then run `flutter run -d linux` again.

Expected: after login completes, the app navigates directly to `/bookings/1/42` rather than `/dashboard`.

- [ ] **Step 4: Verify expiry**

In `lib/core/config/router.dart`, temporarily change `inHours < 24` to `inSeconds < 5`. Relaunch, navigate somewhere, wait 6 seconds, relaunch. Confirm it lands on `/dashboard`. Revert the change when done.

- [ ] **Step 5: Verify logout clears the route**

Navigate to a nested route, then tap logout. Log back in. Confirm the app lands on `/dashboard`, not the previous route.

- [ ] **Step 6: Final commit (revert temp change if needed)**

```bash
flutter analyze
git add -p  # stage only intentional changes
git commit -m "test: manual smoke test complete for screen persistence"
```
