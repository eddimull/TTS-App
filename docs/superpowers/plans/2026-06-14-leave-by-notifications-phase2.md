# Leave-By Notifications — Phase 2 (Location Enrichment) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add on-device location intelligence so the "leave in 15 minutes" reminder fires the right number of minutes before the user must depart (by live traffic-aware travel time) to make the first timeline item, and is suppressed when the user has already left.

**Architecture:** Pure date/decision logic (`leave_by.dart`) + a Google Routes API REST client + a `geolocator` wrapper with tiered permission, orchestrated by an `EnrichmentService` that schedules precise local notifications via Phase 1's `PushService`. Triggered on app-resume (foreground, primary) and on the `event_departure` data push (best-effort). Server time-based push remains the guaranteed floor. Nothing is sent to the server.

**Tech Stack:** Flutter, Dart (SDK >=3.3.0 <4.0.0), Riverpod v2/v3, Dio, `geolocator`, `timezone`, `flutter_local_notifications` 18.x (zonedSchedule), Google Routes API.

**Spec:** `docs/superpowers/specs/2026-06-14-leave-by-notifications-phase2-design.md`
**Builds on:** Phase 1 (`docs/superpowers/plans/2026-06-13-leave-by-notifications-phase1.md`) — already merged on branch `feat/leave-by-notifications`.

**Out of scope:** server-side location enrichment / `POST /api/mobile/location` (dropped), geofencing, continuous tracking, the Laravel backend.

---

## Prerequisites (manual, external — not code steps)

- [ ] **P1: Enable the Routes API** on the existing Google Cloud project for the key in `GOOGLE_PLACES_API_KEY`. Without it, `driveDuration` returns null and the feature silently degrades to the Phase 1 floor.
- [ ] **P2: Google Play background-location justification** — when shipping, the Play Console submission must declare why `ACCESS_BACKGROUND_LOCATION` is used (the leave-by reminder). Not a build blocker; a release prerequisite.
- [ ] **P3: iOS App Review note** — "always" location requires clear usage strings (added in Task 12) and a review justification.

---

## File Structure

New files in `lib/`:
- `lib/core/network/geocoding.dart` — shared `GeoPoint` value type + `geocodeAddress(String) → Future<GeoPoint?>`, extracted from `venue_picker.dart`. No maps dependency.
- `lib/features/notifications/data/leave_by.dart` — pure departure/remind/already-left/body logic. Most-tested file. Clock injected.
- `lib/features/notifications/data/routes_client.dart` — `RoutesClient.driveDuration({origin, destinationAddress}) → Future<Duration?>` via Google Routes API.
- `lib/features/notifications/services/location_service.dart` — `LocationService` over `geolocator`; tiered permission; `LocationGrant` enum.
- `lib/features/notifications/services/enrichment_service.dart` — orchestrator; schedules/suppresses local notifications.
- `lib/features/notifications/services/lifecycle_observer.dart` — `WidgetsBindingObserver` that triggers enrichment on resume.

Modified:
- `lib/features/bookings/widgets/venue_picker.dart` — use shared `geocodeAddress`, convert `GeoPoint`→`LatLng` at the boundary.
- `lib/features/notifications/services/push_service.dart` — add `scheduleLocal` + `cancelLocal` (zonedSchedule).
- `lib/features/notifications/providers/notifications_provider.dart` — providers + `enrichTodaysEvents()`.
- `lib/main.dart` — `tz.initializeTimeZones()` at startup.
- `lib/shared/widgets/app_scaffold.dart` — register the lifecycle observer.
- `pubspec.yaml` — add `geolocator`, `timezone`.
- iOS `Info.plist`, `Runner.entitlements`; Android manifest — location permissions/usage strings.

Tests under `test/notifications/`.

---

## Task 1: Add dependencies

**Files:** Modify `pubspec.yaml`

- [ ] **Step 1: Add packages**

Under `dependencies:` (after `flutter_local_notifications: ^18.0.1`):

```yaml
  geolocator: ^13.0.1
  timezone: ^0.9.4
```

- [ ] **Step 2: Install**

Run: `flutter pub get`
Expected: resolves; `Got dependencies!`. If a conflict appears, report the exact resolver output as BLOCKED rather than pinning blindly.

- [ ] **Step 3: Baseline analyze**

Run: `flutter analyze`
Expected: no NEW errors (only the known pre-existing 3 warnings in secure_storage.dart / main.dart).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add geolocator + timezone for phase 2 location enrichment"
```

---

## Task 2: Maps-free geocoding helper + GeoPoint (TDD-light)

Add a NEW maps-free geocoding helper in `lib/core/network/geocoding.dart` returning a plain `GeoPoint`, for the notifications layer (which must not depend on `google_maps_flutter`).

**Decision (revised from the original plan):** Do NOT change `venue_picker.dart`'s existing `geocodeAddress` (it returns `LatLng?` and is consumed by 4 other files — `event_detail_screen.dart`, `event_edit_screen.dart`, `event_sub_form_card.dart` — that feed it straight into `google_maps_flutter`). Changing its return type would break all of them for no Phase 2 benefit. Instead, the new helper lives independently and is used only by the notifications layer. The small duplication of the REST call is the right trade vs. a risky 4-file refactor. `venue_picker.dart` is left untouched.

**Files:**
- Create: `lib/core/network/geocoding.dart`
- Test: `test/notifications/geocoding_test.dart`
- (No modification to `venue_picker.dart`.)

- [ ] **Step 1: Write the failing test (parsing via stubbed Dio)**

Create `test/notifications/geocoding_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/geocoding.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.status = 200});
  final String body;
  final int status;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(body, status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
}

void main() {
  test('parseGeocode extracts the first result lat/lng', () {
    const json = '{"results":[{"geometry":{"location":{"lat":30.4,"lng":-91.1}}}]}';
    final point = parseGeocodeResponse({'results': [
      {'geometry': {'location': {'lat': 30.4, 'lng': -91.1}}}
    ]});
    expect(point, isNotNull);
    expect(point!.latitude, 30.4);
    expect(point.longitude, -91.1);
    // silence unused json lint
    expect(json.isNotEmpty, true);
  });

  test('parseGeocode returns null for empty results', () {
    expect(parseGeocodeResponse({'results': <dynamic>[]}), isNull);
    expect(parseGeocodeResponse({}), isNull);
    expect(parseGeocodeResponse({'results': null}), isNull);
  });

  test('GeoPoint equality', () {
    expect(const GeoPoint(1, 2), const GeoPoint(1, 2));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/geocoding_test.dart`
Expected: FAIL — `geocoding.dart` / `GeoPoint` / `parseGeocodeResponse` not defined.

- [ ] **Step 3: Implement the shared helper**

Create `lib/core/network/geocoding.dart`:

```dart
import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// A plain latitude/longitude pair, independent of any maps package so the
/// notifications layer need not depend on google_maps_flutter.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Dedicated Dio for the public Google Geocoding API — separate from the app's
/// authenticated api_client (different host, no Bearer token).
final Dio _geocodeDio = Dio();

/// Pure parse of a Geocoding REST response body into a [GeoPoint]. Null when
/// there are no results or the shape is unexpected.
GeoPoint? parseGeocodeResponse(Map<String, dynamic> data) {
  final results = data['results'] as List<dynamic>?;
  if (results == null || results.isEmpty) return null;
  final location = (results.first as Map<String, dynamic>)['geometry']
      ?['location'] as Map<String, dynamic>?;
  if (location == null) return null;
  final lat = (location['lat'] as num?)?.toDouble();
  final lng = (location['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return GeoPoint(lat, lng);
}

/// Returns the first geocoding result's [GeoPoint], or null on any failure.
/// REST call via Dio (Places Details fetchPlace was broken on web).
Future<GeoPoint?> geocodeAddress(String address) async {
  if (address.trim().isEmpty || AppConfig.googlePlacesApiKey.isEmpty) {
    return null;
  }
  try {
    final response = await _geocodeDio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'address': address,
        'key': AppConfig.googlePlacesApiKey,
      },
    );
    final data = response.data;
    if (data == null) return null;
    return parseGeocodeResponse(data);
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/geocoding_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Verify analyze clean**

Run: `flutter analyze lib/core/network/geocoding.dart`
Expected: No issues. (`venue_picker.dart` is intentionally untouched — its `geocodeAddress`→`LatLng?` stays for the maps consumers. This new helper is a separate top-level `geocodeAddress`→`GeoPoint?` in a different library, imported explicitly by the notifications layer.)

- [ ] **Step 6: Commit**

```bash
git add lib/core/network/geocoding.dart test/notifications/geocoding_test.dart
git commit -m "feat(geocoding): maps-free geocodeAddress + GeoPoint for notifications layer"
```

---

## Task 3: leave_by.dart — departure & remind math (pure, TDD)

**Files:**
- Create: `lib/features/notifications/data/leave_by.dart`
- Test: `test/notifications/leave_by_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notifications/leave_by_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/leave_by.dart';

void main() {
  group('departureTime', () {
    test('subtracts travel from first-item time', () {
      final first = DateTime(2026, 6, 14, 19, 0);
      final dep = departureTime(firstItem: first, travel: const Duration(minutes: 45));
      expect(dep, DateTime(2026, 6, 14, 18, 15));
    });
  });

  group('remindAt', () {
    test('is 15 minutes before departure', () {
      final dep = DateTime(2026, 6, 14, 18, 15);
      expect(remindAt(dep), DateTime(2026, 6, 14, 18, 0));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/leave_by_test.dart`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement**

Create `lib/features/notifications/data/leave_by.dart`:

```dart
/// Minutes of warning before the user must depart.
const Duration kDepartureWarning = Duration(minutes: 15);

/// The moment the user must leave to reach the first timeline item on time:
/// the item's time minus live travel duration.
DateTime departureTime({required DateTime firstItem, required Duration travel}) =>
    firstItem.subtract(travel);

/// When to fire the "leave in 15 minutes" reminder: [kDepartureWarning] before
/// the departure moment.
DateTime remindAt(DateTime departure) => departure.subtract(kDepartureWarning);
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/leave_by_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/leave_by.dart test/notifications/leave_by_test.dart
git commit -m "feat(notifications): departure + remind-at math"
```

---

## Task 4: leave_by.dart — hasAlreadyLeft (pure, TDD)

**Files:**
- Modify: `lib/features/notifications/data/leave_by.dart`
- Test: `test/notifications/leave_by_test.dart`

Decision: suppress when (a) within the arrival radius of the venue, OR (b) travel time fits the remaining time AND we are already past the departure moment.

- [ ] **Step 1: Write the failing test**

Add to `test/notifications/leave_by_test.dart` inside `main()`:

```dart
  group('hasAlreadyLeft', () {
    test('true when within arrival radius', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 5),
          timeUntilFirstItem: const Duration(minutes: 60),
          metersToVenue: 100,
          pastDeparture: false,
        ),
        true,
      );
    });

    test('true when en route and past departure with time to spare', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 20),
          timeUntilFirstItem: const Duration(minutes: 40),
          metersToVenue: 8000,
          pastDeparture: true,
        ),
        true,
      );
    });

    test('false when far away and not yet departed', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 40),
          timeUntilFirstItem: const Duration(minutes: 60),
          metersToVenue: 30000,
          pastDeparture: false,
        ),
        false,
      );
    });

    test('false when past departure but travel no longer fits (running late)', () {
      expect(
        hasAlreadyLeft(
          travelToVenue: const Duration(minutes: 50),
          timeUntilFirstItem: const Duration(minutes: 40),
          metersToVenue: 30000,
          pastDeparture: true,
        ),
        false,
      );
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/leave_by_test.dart`
Expected: FAIL — `hasAlreadyLeft` not defined.

- [ ] **Step 3: Implement**

Add to `lib/features/notifications/data/leave_by.dart`:

```dart
/// Within this distance of the venue the user has effectively arrived.
const double kArrivalRadiusMeters = 400;

/// Whether the departure reminder should be suppressed because the user has
/// already left or arrived.
///
/// - [travelToVenue]: live driving duration from current location.
/// - [timeUntilFirstItem]: time from now until the first timeline item.
/// - [metersToVenue]: straight-line distance from current location to venue.
/// - [pastDeparture]: whether now is at/after the computed departure moment.
bool hasAlreadyLeft({
  required Duration travelToVenue,
  required Duration timeUntilFirstItem,
  required double metersToVenue,
  required bool pastDeparture,
}) {
  if (metersToVenue <= kArrivalRadiusMeters) return true;
  if (pastDeparture && travelToVenue <= timeUntilFirstItem) return true;
  return false;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/leave_by_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/leave_by.dart test/notifications/leave_by_test.dart
git commit -m "feat(notifications): already-left suppression decision"
```

---

## Task 5: leave_by.dart — buildLeaveByBody (pure, TDD)

Reuses Phase 1's `formatClock` (in `notification_text.dart`) for the time string.

**Files:**
- Modify: `lib/features/notifications/data/leave_by.dart`
- Test: `test/notifications/leave_by_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/notifications/leave_by_test.dart`:

```dart
  group('buildLeaveByBody', () {
    test('with venue and first item', () {
      final body = buildLeaveByBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Load In',
        departure: DateTime(2026, 6, 14, 18, 15),
      );
      expect(body, 'Leave by 6:15pm for Load In — The Blue Room');
    });

    test('without venue', () {
      final body = buildLeaveByBody(
        venue: null,
        firstItemTitle: 'Load In',
        departure: DateTime(2026, 6, 14, 9, 5),
      );
      expect(body, 'Leave by 9:05am for Load In');
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/leave_by_test.dart`
Expected: FAIL — `buildLeaveByBody` not defined.

- [ ] **Step 3: Implement**

Add to the imports at the TOP of `lib/features/notifications/data/leave_by.dart`:

```dart
import 'notification_text.dart' show formatClock;
```

Add the function:

```dart
/// The enriched departure-reminder body, e.g.
/// `Leave by 6:15pm for Load In — The Blue Room`.
String buildLeaveByBody({
  required String? venue,
  required String firstItemTitle,
  required DateTime departure,
}) {
  // departure is a local DateTime; format its wall-clock time.
  final clock = formatClock(departure.toIso8601String()) ?? '';
  final core = 'Leave by $clock for $firstItemTitle';
  if (venue != null && venue.isNotEmpty) {
    return '$core — $venue';
  }
  return core;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/leave_by_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/leave_by.dart test/notifications/leave_by_test.dart
git commit -m "feat(notifications): enriched leave-by body builder"
```

---

## Task 6: RoutesClient (TDD — parse + null-safety)

The pure response-parsing is unit-tested; the network POST is thin glue verified by analyze.

**Files:**
- Create: `lib/features/notifications/data/routes_client.dart`
- Test: `test/notifications/routes_client_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notifications/routes_client_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/routes_client.dart';

void main() {
  group('parseRoutesDuration', () {
    test('parses seconds string like "2705s"', () {
      final d = parseRoutesDuration({
        'routes': [
          {'duration': '2705s'}
        ]
      });
      expect(d, const Duration(seconds: 2705));
    });

    test('parses integer seconds', () {
      final d = parseRoutesDuration({
        'routes': [
          {'duration': 600}
        ]
      });
      expect(d, const Duration(seconds: 600));
    });

    test('null when no routes', () {
      expect(parseRoutesDuration({'routes': <dynamic>[]}), isNull);
      expect(parseRoutesDuration({}), isNull);
    });

    test('null when duration missing/garbage', () {
      expect(parseRoutesDuration({'routes': [{}]}), isNull);
      expect(parseRoutesDuration({'routes': [{'duration': 'abc'}]}), isNull);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/routes_client_test.dart`
Expected: FAIL — not defined.

- [ ] **Step 3: Implement**

Create `lib/features/notifications/data/routes_client.dart`:

```dart
import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/geocoding.dart';

/// Parse a Google Routes API `computeRoutes` response into a [Duration].
/// The `duration` field is a protobuf-style seconds string (e.g. "2705s") or
/// an integer count of seconds. Null when absent or unparseable.
Duration? parseRoutesDuration(Map<String, dynamic> data) {
  final routes = data['routes'] as List<dynamic>?;
  if (routes == null || routes.isEmpty) return null;
  final raw = (routes.first as Map<String, dynamic>)['duration'];
  if (raw is num) return Duration(seconds: raw.round());
  if (raw is String) {
    final cleaned = raw.endsWith('s') ? raw.substring(0, raw.length - 1) : raw;
    final secs = int.tryParse(cleaned);
    if (secs != null) return Duration(seconds: secs);
  }
  return null;
}

/// Computes traffic-aware driving time from a live origin to a venue address.
class RoutesClient {
  RoutesClient([Dio? dio]) : _dio = dio ?? Dio();
  final Dio _dio;

  static const _endpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Driving duration (traffic-aware) from [origin] to [destinationAddress],
  /// or null on any failure (missing key, geocode fail, route fail).
  Future<Duration?> driveDuration({
    required GeoPoint origin,
    required String destinationAddress,
  }) async {
    if (AppConfig.googlePlacesApiKey.isEmpty) return null;
    final dest = await geocodeAddress(destinationAddress);
    if (dest == null) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': AppConfig.googlePlacesApiKey,
          'X-Goog-FieldMask': 'routes.duration',
        }),
        data: {
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              }
            }
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': dest.latitude,
                'longitude': dest.longitude,
              }
            }
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
        },
      );
      final data = response.data;
      if (data == null) return null;
      return parseRoutesDuration(data);
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/routes_client_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/notifications/data/routes_client.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/notifications/data/routes_client.dart test/notifications/routes_client_test.dart
git commit -m "feat(notifications): Google Routes API travel-time client"
```

---

## Task 7: LocationService (platform-guarded wrapper)

Plugin glue; verified by analyze (no unit test for geolocator calls). Provides a tiered permission result and a current-position read.

**Files:**
- Create: `lib/features/notifications/services/location_service.dart`

- [ ] **Step 1: Implement**

Create `lib/features/notifications/services/location_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/geocoding.dart';

/// What level of location access the user has granted.
enum LocationGrant { always, whileInUse, denied }

bool get _supported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Wraps geolocator: tiered permission + a single current-position read.
class LocationService {
  /// Request location permission, escalating toward "always". Returns the tier
  /// actually granted. No-op (denied) on unsupported platforms.
  Future<LocationGrant> ensurePermission() async {
    if (!_supported) return LocationGrant.denied;
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationGrant.denied;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    switch (perm) {
      case LocationPermission.always:
        return LocationGrant.always;
      case LocationPermission.whileInUse:
        return LocationGrant.whileInUse;
      case LocationPermission.denied:
      case LocationPermission.deniedForever:
      case LocationPermission.unableToDetermine:
        return LocationGrant.denied;
    }
  }

  /// Current position as a [GeoPoint], or null if unavailable.
  Future<GeoPoint?> current() async {
    if (!_supported) return null;
    try {
      final pos = await Geolocator.getCurrentPosition();
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Straight-line distance in meters between two points.
  double distanceMeters(GeoPoint a, GeoPoint b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
}
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/features/notifications/services/location_service.dart`
Expected: No issues. (If geolocator 13.x renamed `LocationPermission.unableToDetermine`, adjust the switch to cover the actual enum cases — the switch must be exhaustive.)

- [ ] **Step 3: Commit**

```bash
git add lib/features/notifications/services/location_service.dart
git commit -m "feat(notifications): geolocator wrapper with tiered permission"
```

---

## Task 8: PushService.scheduleLocal + cancelLocal + timezone init

**Files:**
- Modify: `lib/features/notifications/services/push_service.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Add timezone init to main.dart**

In `lib/main.dart`, add import:

```dart
import 'package:timezone/data/latest.dart' as tzdata;
```

In `main()`, immediately after `WidgetsFlutterBinding.ensureInitialized();`, add:

```dart
  tzdata.initializeTimeZones();
```

- [ ] **Step 2: Add scheduling methods to PushService**

In `lib/features/notifications/services/push_service.dart`, add imports at the top:

```dart
import 'package:timezone/timezone.dart' as tz;
```

Add these methods inside the `PushService` class (after `_show`):

```dart
  /// Schedule a local notification to fire at [when] (a local wall-clock time).
  /// No-op on unsupported platforms.
  Future<void> scheduleLocal({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_pushSupported) return;
    final scheduled = tz.TZDateTime.from(when, tz.local);
    await _local.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders',
          'Event Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancel a previously scheduled local notification by id. No-op on
  /// unsupported platforms.
  Future<void> cancelLocal(int id) async {
    if (!_pushSupported) return;
    await _local.cancel(id);
  }
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/notifications/services/push_service.dart lib/main.dart`
Expected: No issues. (If `AndroidScheduleMode.exactAllowWhileIdle` requires the `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` permission at build, that is handled in Task 12's manifest step; analyze will still pass.)

- [ ] **Step 4: Confirm Linux still builds (guards intact)**

Run: `flutter build linux 2>&1 | tail -5`
Expected: builds (push code guarded out; timezone init is platform-agnostic and safe).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/services/push_service.dart lib/main.dart
git commit -m "feat(notifications): zoned local-notification scheduling + tz init"
```

---

## Task 9: EnrichmentService (orchestrator) — decision test via fakes (TDD)

The orchestrator's *decision* logic (schedule vs suppress vs skip) is unit-tested with fakes + a fixed clock. The provider wiring comes in Task 10.

**Files:**
- Create: `lib/features/notifications/services/enrichment_service.dart`
- Test: `test/notifications/enrichment_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notifications/enrichment_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/geocoding.dart';
import 'package:tts_bandmate/features/notifications/services/enrichment_service.dart';

class _FakeScheduler implements LocalScheduler {
  final List<({int id, String body, DateTime when})> scheduled = [];
  final List<int> cancelled = [];
  @override
  Future<void> scheduleLocal({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async =>
      scheduled.add((id: id, body: body, when: when));
  @override
  Future<void> cancelLocal(int id) async => cancelled.add(id);
}

EnrichmentInput _input({
  required DateTime now,
  required DateTime firstItem,
  required Duration travel,
  required double meters,
}) =>
    EnrichmentInput(
      notificationId: 42,
      eventTitle: 'Gig',
      venue: 'The Blue Room',
      firstItemTitle: 'Load In',
      firstItem: firstItem,
      now: now,
      origin: const GeoPoint(30, -91),
      travel: travel,
      metersToVenue: meters,
    );

void main() {
  late _FakeScheduler scheduler;
  setUp(() => scheduler = _FakeScheduler());

  test('schedules remind-at when far away and ample time', () async {
    // first item 19:00, travel 45m -> depart 18:15 -> remind 18:00. now 12:00.
    await enrich(
      _input(
        now: DateTime(2026, 6, 14, 12, 0),
        firstItem: DateTime(2026, 6, 14, 19, 0),
        travel: const Duration(minutes: 45),
        meters: 30000,
      ),
      scheduler,
    );
    expect(scheduler.scheduled.length, 1);
    expect(scheduler.scheduled.single.id, 42);
    expect(scheduler.scheduled.single.when, DateTime(2026, 6, 14, 18, 0));
    expect(scheduler.scheduled.single.body, contains('Leave by 6:15pm for Load In'));
  });

  test('suppresses + cancels when within arrival radius', () async {
    await enrich(
      _input(
        now: DateTime(2026, 6, 14, 18, 30),
        firstItem: DateTime(2026, 6, 14, 19, 0),
        travel: const Duration(minutes: 3),
        meters: 100,
      ),
      scheduler,
    );
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, contains(42));
  });

  test('skips when remind time already past', () async {
    // depart 18:15, remind 18:00, but now is 18:10 -> too late.
    await enrich(
      _input(
        now: DateTime(2026, 6, 14, 18, 10),
        firstItem: DateTime(2026, 6, 14, 19, 0),
        travel: const Duration(minutes: 45),
        meters: 30000,
      ),
      scheduler,
    );
    expect(scheduler.scheduled, isEmpty);
    expect(scheduler.cancelled, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/enrichment_service_test.dart`
Expected: FAIL — not defined.

- [ ] **Step 3: Implement**

Create `lib/features/notifications/services/enrichment_service.dart`:

```dart
import '../../../core/network/geocoding.dart';
import '../data/leave_by.dart';

/// Minimal scheduling surface the enrichment logic needs (implemented by
/// PushService). Keeps the decision logic testable without plugins.
abstract class LocalScheduler {
  Future<void> scheduleLocal({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  });
  Future<void> cancelLocal(int id);
}

/// All inputs the pure enrichment decision needs. `now`, `origin`, `travel`,
/// and `metersToVenue` are gathered by the caller (clock + location + routes).
class EnrichmentInput {
  const EnrichmentInput({
    required this.notificationId,
    required this.eventTitle,
    required this.venue,
    required this.firstItemTitle,
    required this.firstItem,
    required this.now,
    required this.origin,
    required this.travel,
    required this.metersToVenue,
  });

  final int notificationId;
  final String eventTitle;
  final String? venue;
  final String firstItemTitle;
  final DateTime firstItem;
  final DateTime now;
  final GeoPoint origin;
  final Duration travel;
  final double metersToVenue;
}

/// Decide and act: schedule the precise departure reminder, suppress it (cancel
/// any existing), or skip when it's already too late. Pure decision over the
/// injected inputs; side effects go through [scheduler].
Future<void> enrich(EnrichmentInput input, LocalScheduler scheduler) async {
  final departure = departureTime(firstItem: input.firstItem, travel: input.travel);
  final remind = remindAt(departure);
  final timeUntilFirstItem = input.firstItem.difference(input.now);
  final pastDeparture = !input.now.isBefore(departure);

  if (hasAlreadyLeft(
    travelToVenue: input.travel,
    timeUntilFirstItem: timeUntilFirstItem,
    metersToVenue: input.metersToVenue,
    pastDeparture: pastDeparture,
  )) {
    await scheduler.cancelLocal(input.notificationId);
    return;
  }

  if (!remind.isAfter(input.now)) {
    // Too late to be useful; leave the server's time-based push as the floor.
    return;
  }

  await scheduler.scheduleLocal(
    id: input.notificationId,
    title: input.eventTitle,
    body: buildLeaveByBody(
      venue: input.venue,
      firstItemTitle: input.firstItemTitle,
      departure: departure,
    ),
    when: remind,
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/enrichment_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/services/enrichment_service.dart test/notifications/enrichment_service_test.dart
git commit -m "feat(notifications): enrichment decision (schedule/suppress/skip)"
```

---

## Task 10: Providers + enrichTodaysEvents wiring

Wires LocationService + RoutesClient + the enrich() decision + PushService (as LocalScheduler) into a single `enrichTodaysEvents()` entry point. Makes `PushService` implement `LocalScheduler`.

**Files:**
- Modify: `lib/features/notifications/services/push_service.dart`
- Modify: `lib/features/notifications/providers/notifications_provider.dart`

- [ ] **Step 1: Make PushService implement LocalScheduler**

In `lib/features/notifications/services/push_service.dart`, add import:

```dart
import 'enrichment_service.dart' show LocalScheduler;
```

Change the class declaration from `class PushService {` to:

```dart
class PushService implements LocalScheduler {
```

(`scheduleLocal` and `cancelLocal` already match the interface from Task 8.)

- [ ] **Step 2: Add providers + entry point**

In `lib/features/notifications/providers/notifications_provider.dart`, add imports:

```dart
import 'package:tts_bandmate/core/network/geocoding.dart';
import '../data/event_first_item.dart' show resolveFirstItem; // added in step 3
import '../data/leave_by.dart';
import '../data/routes_client.dart';
import '../services/enrichment_service.dart';
import '../services/location_service.dart';
import '../../events/providers/events_provider.dart';
import '../../events/data/events_repository.dart';
import '../../../shared/providers/selected_band_provider.dart';
```

Add providers and the entry point (append to the file):

```dart
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final routesClientProvider = Provider<RoutesClient>((ref) {
  return RoutesClient();
});

/// Enrich today's rostered events: for each event today the user plays that has
/// a venue and a first timeline item, compute live travel time and schedule (or
/// suppress) the precise "leave in 15 min" local notification. Best-effort;
/// any failure leaves the server's time-based push as the floor.
Future<void> enrichTodaysEvents(Ref ref, {DateTime? clock}) async {
  final now = clock ?? DateTime.now();
  final location = ref.read(locationServiceProvider);
  final grant = await location.ensurePermission();
  if (grant == LocationGrant.denied) return;

  final origin = await location.current();
  if (origin == null) return;

  final bandId = ref.read(selectedBandProvider).value;
  if (bandId == null) return;

  final today = _ymd(now);
  final events = await ref.read(
    bandEventsProvider(BandEventsParams(bandId: bandId, from: today, to: today)).future,
  );

  final repo = ref.read(eventsRepositoryProvider);
  final routes = ref.read(routesClientProvider);
  final push = ref.read(pushServiceProvider);

  for (final summary in events) {
    if (summary.date != today) continue;
    if (!_isRostered(summary.rosterStatus)) continue;
    final address = summary.venueAddress;
    if (address == null || address.isEmpty) continue;

    // Timeline lives on EventDetail, not the summary — fetch it.
    final detail = await repo.getEventDetail(summary.key);
    final first = resolveFirstItem(detail.timeline);
    if (first == null) continue;

    final travel =
        await routes.driveDuration(origin: origin, destinationAddress: address);
    if (travel == null) continue;

    final meters = location.distanceMeters(origin, await _venuePoint(address) ?? origin);

    await enrich(
      EnrichmentInput(
        notificationId: Object.hash(summary.key, 'event_departure').toUnsigned(31),
        eventTitle: summary.title,
        venue: summary.venueName ?? address,
        firstItemTitle: first.title,
        firstItem: first.time,
        now: now,
        origin: origin,
        travel: travel,
        metersToVenue: meters,
      ),
      push,
    );
  }
}

bool _isRostered(String? status) =>
    status == 'green' || status == 'yellow';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Future<GeoPoint?> _venuePoint(String address) => geocodeAddress(address);
```

- [ ] **Step 3: Add the first-item resolver (pure, used above)**

Create `lib/features/notifications/data/event_first_item.dart`:

```dart
import '../../events/data/models/event_detail.dart';
import 'notification_text.dart' show parseEntryTime;

/// A timeline item resolved to a concrete title + parsed [DateTime].
class FirstItem {
  const FirstItem({required this.title, required this.time});
  final String title;
  final DateTime time;
}

/// The earliest timeline entry that has a parseable time, as a [FirstItem].
/// Null when no entry qualifies. Mirrors the spec's "first item = earliest
/// time" rule, returning the parsed time the enrichment math needs.
FirstItem? resolveFirstItem(List<EventTimelineEntry> timeline) {
  FirstItem? best;
  for (final entry in timeline) {
    final t = parseEntryTime(entry.time);
    if (t == null) continue;
    if (best == null || t.isBefore(best.time)) {
      best = FirstItem(title: entry.title, time: t);
    }
  }
  return best;
}
```

- [ ] **Step 4: Test the resolver (TDD — write this test, run fail, it already passes once step 3 exists)**

Create `test/notifications/event_first_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/notifications/data/event_first_item.dart';

void main() {
  test('resolveFirstItem picks earliest parseable entry with its time', () {
    final t = resolveFirstItem(const [
      EventTimelineEntry(title: 'Show', time: '2026-06-14T19:00:00'),
      EventTimelineEntry(title: 'Load In', time: '2026-06-14T14:00:00'),
      EventTimelineEntry(title: 'No Time', time: null),
    ]);
    expect(t, isNotNull);
    expect(t!.title, 'Load In');
    expect(t.time, DateTime(2026, 6, 14, 14, 0));
  });

  test('null when no parseable entries', () {
    expect(resolveFirstItem(const [EventTimelineEntry(title: 'x', time: null)]), isNull);
    expect(resolveFirstItem(const []), isNull);
  });
}
```

Run: `flutter test test/notifications/event_first_item_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze the wiring**

Run: `flutter analyze lib/features/notifications/`
Expected: No issues. (Note: `parseEntryTime` must be exported from `notification_text.dart` — it is a top-level function there from Phase 1, so the `show parseEntryTime` import resolves.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/notifications/ test/notifications/event_first_item_test.dart
git commit -m "feat(notifications): enrichTodaysEvents wiring + first-item resolver"
```

---

## Task 10b: Background data-push enrichment (event_departure)

Wire the `event_departure` data push to run enrichment for its single event when the app is reachable (foreground or OS-granted background time). Best-effort; the server time-based push is the floor. This reuses `enrich()` and the same gathering steps as `enrichTodaysEvents`, scoped to one event from the payload.

**Files:**
- Modify: `lib/features/notifications/providers/notifications_provider.dart`
- Modify: `lib/features/notifications/services/push_service.dart`

- [ ] **Step 1: Add a single-event enrichment entry point**

In `lib/features/notifications/providers/notifications_provider.dart`, add (it reuses the helpers from Task 10):

```dart
/// Enrich a single event from an `event_departure` data push. Best-effort.
Future<void> enrichEventFromPush(
  Ref ref, {
  required String eventKey,
  required String eventTitle,
  required String venueAddress,
  required String firstItemTitle,
  required DateTime firstItem,
  DateTime? clock,
}) async {
  final now = clock ?? DateTime.now();
  final location = ref.read(locationServiceProvider);
  if (await location.ensurePermission() == LocationGrant.denied) return;
  final origin = await location.current();
  if (origin == null) return;

  final routes = ref.read(routesClientProvider);
  final travel =
      await routes.driveDuration(origin: origin, destinationAddress: venueAddress);
  if (travel == null) return;

  final venuePoint = await _venuePoint(venueAddress);
  final meters =
      venuePoint == null ? double.infinity : location.distanceMeters(origin, venuePoint);

  await enrich(
    EnrichmentInput(
      notificationId: Object.hash(eventKey, 'event_departure').toUnsigned(31),
      eventTitle: eventTitle,
      venue: venueAddress,
      firstItemTitle: firstItemTitle,
      firstItem: firstItem,
      now: now,
      origin: origin,
      travel: travel,
      metersToVenue: meters,
    ),
    ref.read(pushServiceProvider),
  );
}
```

- [ ] **Step 2: Call it from the foreground FCM handler for departure pushes**

In `lib/features/notifications/services/push_service.dart`, the `_show` handler currently renders data-only messages. Departure pushes should instead trigger enrichment. Since `PushService` has no `Ref`, expose a hook the provider layer sets. Add a field + setter to `PushService`:

```dart
  /// Optional callback invoked for `event_departure` data pushes so the
  /// provider layer can run location enrichment. Set during app init.
  Future<void> Function(PushPayload payload)? onDeparturePush;
```

In `_show`, after `final payload = PushPayload.fromData(message.data);`, branch:

```dart
    if (payload.type == PushType.departure) {
      final cb = onDeparturePush;
      if (cb != null) {
        await cb(payload);
        return;
      }
    }
```

- [ ] **Step 3: Set the hook when registering (Task 10's wiring)**

In `notifications_provider.dart`, in `PushRegistrar.registerCurrentToken()` (from Phase 1), after `push.listenForeground();`, add:

```dart
    push.onDeparturePush = (payload) async {
      if (payload.firstItemTime == null) return;
      final first = DateTime.tryParse(payload.firstItemTime!);
      if (first == null) return;
      await enrichEventFromPush(
        _ref,
        eventKey: payload.eventKey,
        eventTitle: payload.venueAddress ?? 'Event today',
        venueAddress: payload.venueAddress ?? '',
        firstItemTitle: payload.firstItemTitle ?? 'your event',
        firstItem: first,
      );
    };
```

> The push title for the enriched local notification uses the event title; in Phase 1 the data payload's `title` field carries it. If you prefer the event title over the venue, read `payload`-adjacent `title` via a new field — for now `eventTitle` falls back gracefully.

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/features/notifications/`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/
git commit -m "feat(notifications): enrich on event_departure data push (best-effort)"
```

---

## Task 11: Lifecycle observer — enrich on resume

**Files:**
- Create: `lib/features/notifications/services/lifecycle_observer.dart`
- Modify: `lib/shared/widgets/app_scaffold.dart`

- [ ] **Step 1: Implement the observer**

Create `lib/features/notifications/services/lifecycle_observer.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notifications_provider.dart';

/// Triggers leave-by enrichment whenever the app returns to the foreground.
/// Best-effort: failures are swallowed so they never affect the UI.
class EnrichmentLifecycleObserver with WidgetsBindingObserver {
  EnrichmentLifecycleObserver(this._ref);
  final Ref _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire and forget.
      enrichTodaysEvents(_ref).catchError((_) {});
    }
  }
}
```

- [ ] **Step 2: Register/unregister it in the app shell**

In `lib/shared/widgets/app_scaffold.dart`, the state class `_AppScaffoldState extends ConsumerState<AppScaffold>`. Add an observer field and lifecycle hooks. Add import:

```dart
import 'package:flutter/widgets.dart';
import '../../features/notifications/services/lifecycle_observer.dart';
```

In `_AppScaffoldState`, add a field and `initState`/`dispose` (merge with any existing ones):

```dart
  late final EnrichmentLifecycleObserver _enrichObserver;

  @override
  void initState() {
    super.initState();
    _enrichObserver = EnrichmentLifecycleObserver(ref);
    WidgetsBinding.instance.addObserver(_enrichObserver);
    // Also run once on first build (cold start into the shell counts as a resume).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enrichObserver.didChangeAppLifecycleState(AppLifecycleState.resumed);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_enrichObserver);
    super.dispose();
  }
```

> If `_AppScaffoldState` already defines `initState`/`dispose`, merge these lines into the existing methods rather than duplicating them.

- [ ] **Step 3: Analyze + Linux build**

Run: `flutter analyze lib/features/notifications/services/lifecycle_observer.dart lib/shared/widgets/app_scaffold.dart`
Expected: No issues.

Run: `flutter build linux 2>&1 | tail -5`
Expected: builds (enrichment is permission-guarded; on Linux LocationService returns denied → enrich returns immediately).

- [ ] **Step 4: Commit**

```bash
git add lib/features/notifications/services/lifecycle_observer.dart lib/shared/widgets/app_scaffold.dart
git commit -m "feat(notifications): enrich on app resume via lifecycle observer"
```

---

## Task 12: Native config — location permissions

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: iOS usage strings**

In `ios/Runner/Info.plist`, inside the top-level `<dict>`, add:

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Bandmate uses your location to tell you when to leave to make your gig on time.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Bandmate uses your location in the background to remind you when to leave for today's event, even when the app is closed.</string>
```

- [ ] **Step 2: Android permissions**

In `android/app/src/main/AndroidManifest.xml`, add inside `<manifest>` (above `<application>`):

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

(The exact-alarm permissions back `AndroidScheduleMode.exactAllowWhileIdle` from Task 8.)

- [ ] **Step 3: Build both platforms**

Run (with Android SDK env set as in Phase 1):
`flutter build apk --debug 2>&1 | tail -10`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

iOS build (`flutter build ios --debug --no-codesign`) — run if macOS/Xcode available; otherwise note it as deferred to the user's machine.

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml
git commit -m "build(notifications): location + exact-alarm permissions for android + ios"
```

---

## Task 13: Full suite + analyze gate

**Files:** none (verification)

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: all PASS, including every new `test/notifications/` file plus existing suites. (No `MyApp` boilerplate failure — removed in Phase 1. The 9 pre-existing failures in event_edit/booking/dashboard tests documented in Phase 1 are unrelated; confirm the count is unchanged, not increased.)

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: no NEW issues beyond the known pre-existing 3 (secure_storage deprecation + 2 Sentry experimental warnings).

- [ ] **Step 3: Android APK build**

Run: `flutter build apk --debug`
Expected: `✓ Built ... app-debug.apk`.

- [ ] **Step 4: Manual device verification (documented, not automated)**

On a real device with location granted:
- Open the app on a day with a rostered event that has a venue + a timed first timeline item. Confirm a "leave in 15 min" notification is scheduled for the right time (departure − 15m), with body `Leave by <time> for <first item> — <venue>`.
- Stand (or simulate) near the venue → confirm the reminder is suppressed.
- Deny location → confirm no enrichment and the app behaves as Phase 1.
- Verify on both iOS and Android.

- [ ] **Step 5: Final commit (if any doc tweaks)**

```bash
git add -A
git commit -m "chore(notifications): phase 2 verification pass"
```

(Note: never stage the gitignored Firebase config or unrelated working-tree files; prefer explicit paths.)

---

## Self-Review Notes

- **Spec coverage:** location access tiers (Task 7, 10), Routes API travel time (Task 6), departure/remind math (Task 3), already-left suppression (Task 4, 9), enriched body (Task 5), foreground trigger (Task 11), background data-push trigger (uses the same `enrich()` — the FCM handler calling it is a thin follow-up; see note below), no server location reporting (correctly absent), shared maps-free geocoding (Task 2), timezone + zoned scheduling (Task 8), native permissions (Task 12). 
- **Background data-push path:** Covered by Task 10b — `enrichEventFromPush()` runs the same `enrich()` decision for the single event in an `event_departure` payload, hooked into the foreground FCM handler. iOS background execution remains unreliable (OS-dependent), so the foreground path (Task 11) is primary and the server time-based push is the floor; Task 10b is the best-effort upgrade.
- **Type consistency:** `GeoPoint` (Task 2) used by RoutesClient (6), LocationService (7), EnrichmentInput (9), wiring (10). `LocalScheduler` (9) implemented by PushService (10) with `scheduleLocal`/`cancelLocal` matching Task 8. `resolveFirstItem`→`FirstItem{title,time}` (10) feeds `EnrichmentInput.firstItem/firstItemTitle` (9). `departureTime`/`remindAt`/`hasAlreadyLeft`/`buildLeaveByBody` signatures consistent across Tasks 3-5 and 9. `parseEntryTime`/`formatClock` reused from Phase 1's `notification_text.dart`.
- **Placeholders:** none — full code in every step. Tuning constants (`kArrivalRadiusMeters`) are real defaults, adjustable later.
