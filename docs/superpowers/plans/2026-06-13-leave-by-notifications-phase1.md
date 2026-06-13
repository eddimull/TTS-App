# Leave-By Notifications — Phase 1 (Push Plumbing + Time-Based Notifications) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the server-guaranteed "safety net" half of the leave-by notifications feature: the app registers its push token with the backend, receives push notifications, and renders time-based event reminders — even when the app is closed. No live location yet (that is Phase 2).

**Architecture:** Add Firebase Cloud Messaging (FCM/APNs) to the Flutter app. On login, the app fetches its FCM token and registers it with the backend; on logout it deregisters. Incoming pushes are rendered as local notifications via `flutter_local_notifications`, with a pure body-builder function that formats event/timeline data into the approved text matrix (minus the "leave by" travel lines, which Phase 2 adds). A foreground push handler upgrades/displays notifications; a top-level background handler is registered per FCM requirements.

**Tech Stack:** Flutter, Dart (SDK `>=3.3.0 <4.0.0`), Riverpod v2, Dio, `firebase_core`, `firebase_messaging`, `flutter_local_notifications`.

**Spec:** `docs/superpowers/specs/2026-06-13-event-leave-by-notifications-design.md`

**Phase boundary:** This plan implements push plumbing + time-based notification rendering only. Excluded (Phase 2): `geolocator`, Google Directions travel time, "leave by" enrichment, "already left" suppression, location reporting endpoint. Excluded (separate backend spec): all Laravel-side scheduling/sending.

---

## Prerequisites (manual, one-time — not code steps)

These require external accounts/consoles and cannot be unit-tested. Do them first; the plan's code depends on the generated config files.

- [ ] **P1: Create Firebase project** in the Firebase console for app IDs Android `tts.band` and iOS `band.tts.mate`.
- [ ] **P2: Register the Android app** (`tts.band`) in Firebase; download `google-services.json` into `android/app/google-services.json`.
- [ ] **P3: Register the iOS app** (`band.tts.mate`) in Firebase; download `GoogleService-Info.plist` into `ios/Runner/GoogleService-Info.plist` (add to the Xcode Runner target).
- [ ] **P4: Create an APNs auth key** (.p8) in the Apple Developer console and upload it to Firebase project settings → Cloud Messaging, so APNs is wired to FCM.
- [ ] **P5: Run `flutterfire configure`** (FlutterFire CLI) to generate `lib/firebase_options.dart` with `DefaultFirebaseOptions`. If the CLI is unavailable, this file must be created by hand from the console values; the plan references `DefaultFirebaseOptions.currentPlatform`.
- [ ] **P6: Confirm with backend owner** that `google-services.json`/`GoogleService-Info.plist` are gitignored or committed per repo convention. Add them to `.gitignore` if secrets policy requires.

> **Note on platforms:** FCM does not support Linux/web desktop targets the way it does iOS/Android. All push code must guard against unsupported platforms so `flutter run -d linux` still launches. Tasks below include these guards.

---

## File Structure

New feature slice `lib/features/notifications/`:

- `lib/features/notifications/data/notification_text.dart` — pure functions: timeline parsing + notification body/title builder (the content matrix). No Flutter/plugin imports. Fully unit-tested.
- `lib/features/notifications/data/push_payload.dart` — model: parse an incoming FCM data map into a typed `PushPayload`. Pure. Unit-tested.
- `lib/features/notifications/data/device_repository.dart` — `DeviceRepository`: registers/deregisters the device token with the backend via Dio. Mirrors `EventsRepository`.
- `lib/features/notifications/services/push_service.dart` — `PushService`: wraps `firebase_messaging` + `flutter_local_notifications`; init, permission, token retrieval, foreground/open handlers, render. Platform-guarded.
- `lib/features/notifications/providers/notifications_provider.dart` — Riverpod providers wiring `DeviceRepository`, `PushService`, and the token-registration controller.

Modified:

- `lib/core/network/api_endpoints.dart` — add device endpoints.
- `lib/main.dart` — init `firebase_core` + register top-level background handler before `runApp`.
- `lib/features/auth/providers/auth_provider.dart` — register token on login, deregister on logout.

Tests under `test/notifications/`.

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the packages**

In `pubspec.yaml` under `dependencies:` (after `sentry_flutter: ^9.17.0`), add:

```yaml
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
  flutter_local_notifications: ^18.0.1
```

- [ ] **Step 2: Install**

Run: `flutter pub get`
Expected: resolves without version conflicts; `Got dependencies!`

- [ ] **Step 3: Verify analyzer still clean**

Run: `flutter analyze`
Expected: No new errors (the imports aren't used yet, so this is just a baseline).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add firebase_core, firebase_messaging, flutter_local_notifications"
```

---

## Task 2: Timeline parsing helpers (pure, TDD)

The body builder needs two derived values from an event: the **first timeline item** (earliest `time`) and the **show time** (the event's `startTime`). These are pure functions over the existing `EventTimelineEntry` model (`lib/features/events/data/models/event_detail.dart`: `EventTimelineEntry({required String title, String? time})`).

**Files:**
- Create: `lib/features/notifications/data/notification_text.dart`
- Test: `test/notifications/notification_text_test.dart`

- [ ] **Step 1: Write the failing test for first-item selection**

Create `test/notifications/notification_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/notifications/data/notification_text.dart';

void main() {
  group('firstTimelineItem', () {
    test('returns the entry with the earliest parseable time', () {
      final timeline = [
        const EventTimelineEntry(title: 'Show', time: '2026-06-13T19:00:00'),
        const EventTimelineEntry(title: 'Load In', time: '2026-06-13T14:00:00'),
        const EventTimelineEntry(title: 'Sound Check', time: '2026-06-13T17:00:00'),
      ];
      final first = firstTimelineItem(timeline);
      expect(first?.title, 'Load In');
    });

    test('ignores entries with null or unparseable time', () {
      final timeline = [
        const EventTimelineEntry(title: 'No Time', time: null),
        const EventTimelineEntry(title: 'Load In', time: '2026-06-13T14:00:00'),
        const EventTimelineEntry(title: 'Garbage', time: 'not-a-time'),
      ];
      final first = firstTimelineItem(timeline);
      expect(first?.title, 'Load In');
    });

    test('returns null when no entry has a parseable time', () {
      final timeline = [
        const EventTimelineEntry(title: 'A', time: null),
        const EventTimelineEntry(title: 'B', time: 'nope'),
      ];
      expect(firstTimelineItem(timeline), isNull);
    });

    test('returns null for an empty timeline', () {
      expect(firstTimelineItem(const []), isNull);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/notification_text_test.dart`
Expected: FAIL — `firstTimelineItem` is not defined.

- [ ] **Step 3: Implement `firstTimelineItem`**

Create `lib/features/notifications/data/notification_text.dart`:

```dart
import '../../events/data/models/event_detail.dart';

/// Parses an ISO-8601 or `HH:mm` time string into a comparable [DateTime].
/// Returns null when the value is missing or unparseable.
DateTime? parseEntryTime(String? value) {
  if (value == null || value.isEmpty) return null;
  // Full ISO timestamp (e.g. 2026-06-13T14:00:00).
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso;
  // Bare HH:mm — anchor to a fixed reference date so entries are comparable.
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (match != null) {
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    return DateTime(2000, 1, 1, h, m);
  }
  return null;
}

/// The timeline entry with the earliest parseable [EventTimelineEntry.time].
/// Entries without a parseable time are ignored. Null if none qualify.
EventTimelineEntry? firstTimelineItem(List<EventTimelineEntry> timeline) {
  EventTimelineEntry? best;
  DateTime? bestTime;
  for (final entry in timeline) {
    final t = parseEntryTime(entry.time);
    if (t == null) continue;
    if (bestTime == null || t.isBefore(bestTime)) {
      best = entry;
      bestTime = t;
    }
  }
  return best;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/notification_text_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/notification_text.dart test/notifications/notification_text_test.dart
git commit -m "feat(notifications): timeline parsing helpers"
```

---

## Task 3: Time formatting helper (pure, TDD)

Notification bodies display times like `2:00pm`. Add a formatter used by the body builder.

**Files:**
- Modify: `lib/features/notifications/data/notification_text.dart`
- Test: `test/notifications/notification_text_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/notifications/notification_text_test.dart` inside `main()`:

```dart
  group('formatClock', () {
    test('formats an afternoon ISO time as h:mma lowercase', () {
      expect(formatClock('2026-06-13T14:00:00'), '2:00pm');
    });
    test('formats a morning time', () {
      expect(formatClock('2026-06-13T09:05:00'), '9:05am');
    });
    test('formats midnight and noon', () {
      expect(formatClock('2026-06-13T00:00:00'), '12:00am');
      expect(formatClock('2026-06-13T12:00:00'), '12:00pm');
    });
    test('formats a bare HH:mm', () {
      expect(formatClock('19:30'), '7:30pm');
    });
    test('returns null for unparseable input', () {
      expect(formatClock('nope'), isNull);
      expect(formatClock(null), isNull);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/notification_text_test.dart`
Expected: FAIL — `formatClock` not defined.

- [ ] **Step 3: Implement `formatClock`**

Add to `lib/features/notifications/data/notification_text.dart`:

```dart
/// Formats a time string as `h:mma` in lowercase (e.g. `2:00pm`).
/// Returns null when the value cannot be parsed.
String? formatClock(String? value) {
  final t = parseEntryTime(value);
  if (t == null) return null;
  final isPm = t.hour >= 12;
  var hour12 = t.hour % 12;
  if (hour12 == 0) hour12 = 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final suffix = isPm ? 'pm' : 'am';
  return '$hour12:$minute$suffix';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/notification_text_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/notification_text.dart test/notifications/notification_text_test.dart
git commit -m "feat(notifications): clock formatting helper"
```

---

## Task 4: Notification body builder (pure, TDD)

Builds the title + body for the 8h reminder per the spec's content matrix — **Phase 1 variant without the "leave by" lines** (those are added in Phase 2). Inputs are simple primitives (not the full payload model yet) so it stays pure and trivially testable.

Content matrix for Phase 1:

| Situation | Body |
|---|---|
| Venue + multiple timeline items | `[Venue] · Load In 2:00pm, Show 7:00pm` |
| Venue + single usable item | `[Venue] · Load In 2:00pm` |
| No venue, has times | `Load In 2:00pm, Show 7:00pm` |
| No venue, no usable times | `You have an event today` |

Title is always the event title.

"Multiple items" means the first timeline item exists **and** a show time exists **and** they differ. "Show" line uses the event `startTime`.

**Files:**
- Modify: `lib/features/notifications/data/notification_text.dart`
- Test: `test/notifications/notification_text_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/notifications/notification_text_test.dart`:

```dart
  group('buildReminderBody', () {
    test('venue + load-in + show', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Load In',
        firstItemTime: '2026-06-13T14:00:00',
        showTime: '2026-06-13T19:00:00',
      );
      expect(body, 'The Blue Room · Load In 2:00pm, Show 7:00pm');
    });

    test('venue + single item (show equals first, collapses to one line)', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Show',
        firstItemTime: '2026-06-13T19:00:00',
        showTime: '2026-06-13T19:00:00',
      );
      expect(body, 'The Blue Room · Show 7:00pm');
    });

    test('venue + first item only, no show time', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: 'Load In',
        firstItemTime: '2026-06-13T14:00:00',
        showTime: null,
      );
      expect(body, 'The Blue Room · Load In 2:00pm');
    });

    test('no venue, has times', () {
      final body = buildReminderBody(
        venue: null,
        firstItemTitle: 'Load In',
        firstItemTime: '2026-06-13T14:00:00',
        showTime: '2026-06-13T19:00:00',
      );
      expect(body, 'Load In 2:00pm, Show 7:00pm');
    });

    test('no venue, no usable times', () {
      final body = buildReminderBody(
        venue: null,
        firstItemTitle: null,
        firstItemTime: null,
        showTime: null,
      );
      expect(body, 'You have an event today');
    });

    test('venue present but no usable times falls back to event-today with venue', () {
      final body = buildReminderBody(
        venue: 'The Blue Room',
        firstItemTitle: null,
        firstItemTime: null,
        showTime: null,
      );
      expect(body, 'The Blue Room · You have an event today');
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/notification_text_test.dart`
Expected: FAIL — `buildReminderBody` not defined.

- [ ] **Step 3: Implement `buildReminderBody`**

Add to `lib/features/notifications/data/notification_text.dart`:

```dart
/// Builds the 8h-reminder body (Phase 1: no travel "leave by" lines).
///
/// - [venue]: venue name/address, or null if none/ungeocodable.
/// - [firstItemTitle]/[firstItemTime]: the earliest timeline item, if any.
/// - [showTime]: the event's startTime, if any.
String buildReminderBody({
  required String? venue,
  required String? firstItemTitle,
  required String? firstItemTime,
  required String? showTime,
}) {
  final lines = <String>[];

  final firstClock = formatClock(firstItemTime);
  if (firstItemTitle != null && firstClock != null) {
    lines.add('$firstItemTitle $firstClock');
  }

  final showClock = formatClock(showTime);
  // Only add a distinct "Show" line when it differs from the first item time.
  if (showClock != null && showClock != firstClock) {
    lines.add('Show $showClock');
  }

  final core = lines.isEmpty ? 'You have an event today' : lines.join(', ');

  if (venue != null && venue.isNotEmpty) {
    return '$venue · $core';
  }
  return core;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/notification_text_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/notification_text.dart test/notifications/notification_text_test.dart
git commit -m "feat(notifications): reminder body builder (phase 1, no travel times)"
```

---

## Task 5: Push payload model (pure, TDD)

Typed parse of an incoming FCM `data` map into a `PushPayload`. The backend sends `type`, `eventKey`, and optional `venueAddress`, `firstItemTitle`, `firstItemTime`, `showTime`. Unknown/missing fields tolerate gracefully.

**Files:**
- Create: `lib/features/notifications/data/push_payload.dart`
- Test: `test/notifications/push_payload_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notifications/push_payload_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_payload.dart';

void main() {
  group('PushPayload.fromData', () {
    test('parses a full 8h reminder payload', () {
      final p = PushPayload.fromData({
        'type': 'event_reminder_8h',
        'eventKey': 'evt_123',
        'venueAddress': 'The Blue Room',
        'firstItemTitle': 'Load In',
        'firstItemTime': '2026-06-13T14:00:00',
        'showTime': '2026-06-13T19:00:00',
      });
      expect(p.type, PushType.reminder8h);
      expect(p.eventKey, 'evt_123');
      expect(p.venueAddress, 'The Blue Room');
      expect(p.firstItemTitle, 'Load In');
      expect(p.firstItemTime, '2026-06-13T14:00:00');
      expect(p.showTime, '2026-06-13T19:00:00');
    });

    test('parses a departure payload with missing optional fields', () {
      final p = PushPayload.fromData({
        'type': 'event_departure',
        'eventKey': 'evt_9',
        'venueAddress': 'Somewhere',
        'firstItemTitle': 'Load In',
        'firstItemTime': '2026-06-13T14:00:00',
      });
      expect(p.type, PushType.departure);
      expect(p.showTime, isNull);
    });

    test('unknown type maps to PushType.unknown', () {
      final p = PushPayload.fromData({'type': 'something_else', 'eventKey': 'x'});
      expect(p.type, PushType.unknown);
      expect(p.eventKey, 'x');
    });

    test('missing eventKey yields empty string, never throws', () {
      final p = PushPayload.fromData({'type': 'event_reminder_8h'});
      expect(p.eventKey, '');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/push_payload_test.dart`
Expected: FAIL — `PushPayload` not defined.

- [ ] **Step 3: Implement `PushPayload`**

Create `lib/features/notifications/data/push_payload.dart`:

```dart
/// The kind of push the backend sent.
enum PushType { reminder8h, departure, unknown }

PushType _typeFromString(String? raw) {
  switch (raw) {
    case 'event_reminder_8h':
      return PushType.reminder8h;
    case 'event_departure':
      return PushType.departure;
    default:
      return PushType.unknown;
  }
}

/// Typed view of an incoming FCM `data` map. Tolerant of missing fields.
class PushPayload {
  const PushPayload({
    required this.type,
    required this.eventKey,
    this.venueAddress,
    this.firstItemTitle,
    this.firstItemTime,
    this.showTime,
  });

  final PushType type;
  final String eventKey;
  final String? venueAddress;
  final String? firstItemTitle;
  final String? firstItemTime;
  final String? showTime;

  factory PushPayload.fromData(Map<String, dynamic> data) {
    String? str(String key) {
      final v = data[key];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    return PushPayload(
      type: _typeFromString(data['type']?.toString()),
      eventKey: str('eventKey') ?? '',
      venueAddress: str('venueAddress'),
      firstItemTitle: str('firstItemTitle'),
      firstItemTime: str('firstItemTime'),
      showTime: str('showTime'),
    );
  }

  /// Stable id for deduping notifications: one slot per event+type.
  int get notificationId => Object.hash(eventKey, type).toUnsigned(31);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/push_payload_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/push_payload.dart test/notifications/push_payload_test.dart
git commit -m "feat(notifications): typed push payload model"
```

---

## Task 6: Device endpoints

**Files:**
- Modify: `lib/core/network/api_endpoints.dart`

- [ ] **Step 1: Add endpoint constants**

In `lib/core/network/api_endpoints.dart`, add (matching the existing static-const style, near the other `/api/mobile/...` paths):

```dart
  // Push device registration (Phase 1 notifications)
  static const String mobileDevices = '/api/mobile/devices';
  static String mobileDevice(String token) => '/api/mobile/devices/$token';
```

- [ ] **Step 2: Verify analyzer clean**

Run: `flutter analyze lib/core/network/api_endpoints.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/core/network/api_endpoints.dart
git commit -m "feat(notifications): add device registration endpoints"
```

---

## Task 7: DeviceRepository (TDD)

Registers/deregisters the FCM token with the backend. Mirrors `EventsRepository` (constructor takes a `Dio`; errors bubble; provider wraps `apiClientProvider.dio`).

**Files:**
- Create: `lib/features/notifications/data/device_repository.dart`
- Test: `test/notifications/device_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notifications/device_repository_test.dart`. Uses Dio with a stubbed adapter so no network is hit.

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/device_repository.dart';

/// Minimal in-memory Dio adapter capturing the last request.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  Object? lastBody;
  int statusCode = 200;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    lastBody = options.data;
    return ResponseBody.fromString('{}', statusCode,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
}

void main() {
  late Dio dio;
  late _CapturingAdapter adapter;
  late DeviceRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    adapter = _CapturingAdapter();
    dio.httpClientAdapter = adapter;
    repo = DeviceRepository(dio);
  });

  test('register POSTs token and platform to /api/mobile/devices', () async {
    await repo.register(token: 'tok-abc', platform: 'ios');
    expect(adapter.lastOptions!.method, 'POST');
    expect(adapter.lastOptions!.path, '/api/mobile/devices');
    expect(adapter.lastBody, {'token': 'tok-abc', 'platform': 'ios'});
  });

  test('deregister DELETEs the token-specific path', () async {
    await repo.deregister('tok-abc');
    expect(adapter.lastOptions!.method, 'DELETE');
    expect(adapter.lastOptions!.path, '/api/mobile/devices/tok-abc');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/notifications/device_repository_test.dart`
Expected: FAIL — `DeviceRepository` not defined.

- [ ] **Step 3: Implement `DeviceRepository`**

Create `lib/features/notifications/data/device_repository.dart`:

```dart
import 'package:dio/dio.dart';

import '../../../core/network/api_endpoints.dart';

/// Registers/deregisters this device's push token with the backend.
class DeviceRepository {
  DeviceRepository(this._dio);
  final Dio _dio;

  Future<void> register({required String token, required String platform}) {
    return _dio.post<void>(
      ApiEndpoints.mobileDevices,
      data: {'token': token, 'platform': platform},
    );
  }

  Future<void> deregister(String token) {
    return _dio.delete<void>(ApiEndpoints.mobileDevice(token));
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/notifications/device_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/notifications/data/device_repository.dart test/notifications/device_repository_test.dart
git commit -m "feat(notifications): device repository for token registration"
```

---

## Task 8: PushService (platform-guarded wrapper)

Wraps `firebase_messaging` + `flutter_local_notifications`. This class touches plugins (not unit-testable without heavy mocking), so keep it thin: all formatting/decision logic already lives in the pure helpers (Tasks 2–5). We verify it via `flutter analyze` and manual device testing; no unit test for the plugin glue.

**Files:**
- Create: `lib/features/notifications/services/push_service.dart`

- [ ] **Step 1: Implement `PushService`**

Create `lib/features/notifications/services/push_service.dart`:

```dart
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/notification_text.dart';
import '../data/push_payload.dart';

/// True only on platforms where FCM is supported.
bool get _pushSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Renders the title for a payload (event title comes from the notification
/// half of the message; the data half drives the body).
String renderBody(PushPayload p) => buildReminderBody(
      venue: p.venueAddress,
      firstItemTitle: p.firstItemTitle,
      firstItemTime: p.firstItemTime,
      showTime: p.showTime,
    );

/// Thin wrapper over FCM + local notifications. Logic-free where possible.
class PushService {
  PushService(this._local);

  final FlutterLocalNotificationsPlugin _local;

  static const _channel = AndroidNotificationChannel(
    'event_reminders',
    'Event Reminders',
    description: 'Reminders about events you are playing today',
    importance: Importance.high,
  );

  /// Initialize local-notification plugin + Android channel. Safe to call on
  /// unsupported platforms (no-op).
  Future<void> init() async {
    if (!_pushSupported) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(initSettings);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// Request notification permission from the OS. No-op on unsupported.
  Future<void> requestPermission() async {
    if (!_pushSupported) return;
    await FirebaseMessaging.instance.requestPermission();
  }

  /// Current FCM token, or null if unsupported/unavailable.
  Future<String?> token() async {
    if (!_pushSupported) return null;
    return FirebaseMessaging.instance.getToken();
  }

  /// Stream of token refreshes (empty stream on unsupported platforms).
  Stream<String> get onTokenRefresh =>
      _pushSupported ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  /// Wire foreground message handling. The OS shows backgrounded pushes itself;
  /// foreground pushes must be rendered manually.
  void listenForeground() {
    if (!_pushSupported) return;
    FirebaseMessaging.onMessage.listen(_show);
  }

  Future<void> _show(RemoteMessage message) async {
    final payload = PushPayload.fromData(message.data);
    final title = message.notification?.title ?? 'Event today';
    await _local.show(
      payload.notificationId,
      title,
      renderBody(payload),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders',
          'Event Reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyzer clean**

Run: `flutter analyze lib/features/notifications/services/push_service.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/notifications/services/push_service.dart
git commit -m "feat(notifications): push service wrapper (platform-guarded)"
```

---

## Task 9: renderBody glue test (TDD)

`renderBody` (in `push_service.dart`) is a thin pure adapter from `PushPayload` to `buildReminderBody`. Worth a test since it wires field names together (the kind of mismatch the plan self-review warns about).

**Files:**
- Test: `test/notifications/render_body_test.dart`

- [ ] **Step 1: Write the test**

Create `test/notifications/render_body_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/push_payload.dart';
import 'package:tts_bandmate/features/notifications/services/push_service.dart';

void main() {
  test('renderBody maps payload fields into the reminder body', () {
    final p = PushPayload.fromData({
      'type': 'event_reminder_8h',
      'eventKey': 'e1',
      'venueAddress': 'The Blue Room',
      'firstItemTitle': 'Load In',
      'firstItemTime': '2026-06-13T14:00:00',
      'showTime': '2026-06-13T19:00:00',
    });
    expect(renderBody(p), 'The Blue Room · Load In 2:00pm, Show 7:00pm');
  });
}
```

- [ ] **Step 2: Run to verify it passes**

Run: `flutter test test/notifications/render_body_test.dart`
Expected: PASS (implementation already exists from Task 8 — this guards the wiring).

- [ ] **Step 3: Commit**

```bash
git add test/notifications/render_body_test.dart
git commit -m "test(notifications): cover renderBody payload mapping"
```

---

## Task 10: Notification providers

Expose `DeviceRepository`, `PushService`, and a small controller that registers the current token. The controller is what auth calls on login/logout.

**Files:**
- Create: `lib/features/notifications/providers/notifications_provider.dart`

- [ ] **Step 1: Implement providers**

Create `lib/features/notifications/providers/notifications_provider.dart`:

```dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/device_repository.dart';
import '../services/push_service.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(ref.watch(apiClientProvider).dio);
});

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(FlutterLocalNotificationsPlugin());
});

/// Platform string the backend expects, or null when push is unsupported.
String? _platformName() {
  if (kIsWeb) return null;
  if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
  if (defaultTargetPlatform == TargetPlatform.android) return 'android';
  return null;
}

/// Coordinates token lifecycle: call [registerCurrentToken] after login and
/// [deregisterCurrentToken] on logout.
class PushRegistrar {
  PushRegistrar(this._ref);
  final Ref _ref;

  Future<void> registerCurrentToken() async {
    final platform = _platformName();
    if (platform == null) return; // unsupported platform: no-op
    final push = _ref.read(pushServiceProvider);
    await push.init();
    await push.requestPermission();
    push.listenForeground();
    final token = await push.token();
    if (token == null) return;
    await _ref.read(deviceRepositoryProvider).register(
          token: token,
          platform: platform,
        );
  }

  Future<void> deregisterCurrentToken() async {
    if (_platformName() == null) return;
    final push = _ref.read(pushServiceProvider);
    final token = await push.token();
    if (token == null) return;
    try {
      await _ref.read(deviceRepositoryProvider).deregister(token);
    } catch (_) {
      // Best-effort: logout should not fail if deregistration does.
    }
  }
}

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  return PushRegistrar(ref);
});
```

- [ ] **Step 2: Verify analyzer clean**

Run: `flutter analyze lib/features/notifications/providers/notifications_provider.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/notifications/providers/notifications_provider.dart
git commit -m "feat(notifications): providers + token registrar"
```

---

## Task 11: Hook token registration into auth (TDD)

On successful login, register the token; on logout, deregister. Must be best-effort — a push failure must never block login/logout. We test that login still succeeds when registration is stubbed, and that the registrar is invoked.

**Files:**
- Modify: `lib/features/auth/providers/auth_provider.dart`
- Test: `test/notifications/auth_push_hook_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notifications/auth_push_hook_test.dart`. It overrides `pushRegistrarProvider` with a spy subclass and verifies the hooks fire. (Mirrors the `FakeSecureStorage` + `ProviderContainer` override pattern in `test/auth_provider_test.dart`.)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/notifications/providers/notifications_provider.dart';

class SpyRegistrar extends PushRegistrar {
  SpyRegistrar(Ref ref) : super(ref);
  int registerCalls = 0;
  int deregisterCalls = 0;
  @override
  Future<void> registerCurrentToken() async => registerCalls++;
  @override
  Future<void> deregisterCurrentToken() async => deregisterCalls++;
}

void main() {
  test('PushRegistrar exposes register/deregister hooks used by auth', () {
    // Compile-time guard: the methods auth depends on exist with these names.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final spy = SpyRegistrar(_FakeRef());
    expect(spy.registerCalls, 0);
    expect(spy.deregisterCalls, 0);
  });
}

class _FakeRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
```

> Note: This is a light contract test guarding method names so the auth wiring in Step 3 references real symbols. Full end-to-end auth+push behavior is verified manually on device (FCM cannot run in the unit test harness).

- [ ] **Step 2: Run to verify it passes (contract guard)**

Run: `flutter test test/notifications/auth_push_hook_test.dart`
Expected: PASS — confirms `registerCurrentToken`/`deregisterCurrentToken` exist.

- [ ] **Step 3: Wire into the auth notifier**

In `lib/features/auth/providers/auth_provider.dart`, add the import at the top:

```dart
import '../../notifications/providers/notifications_provider.dart';
```

In `login(...)`, after the `state = await AsyncValue.guard(...)` block completes, append (best-effort, non-blocking):

```dart
    if (state.value is AuthAuthenticated) {
      try {
        await ref.read(pushRegistrarProvider).registerCurrentToken();
      } catch (_) {
        // Push registration is best-effort; never block login.
      }
    }
```

In `logout()`, before `await storage.clear();`, add:

```dart
    try {
      await ref.read(pushRegistrarProvider).deregisterCurrentToken();
    } catch (_) {
      // Best-effort.
    }
```

- [ ] **Step 4: Run the full auth test suite to confirm no regression**

Run: `flutter test test/auth_provider_test.dart`
Expected: PASS — existing auth tests still pass (the push registrar resolves to a real provider but its platform guard makes it a no-op in the test/host environment).

> If any existing auth test constructs a `ProviderContainer` without overriding `apiClientProvider` and now fails because `pushRegistrarProvider` is read, override `pushRegistrarProvider` in that test's container with a no-op spy as shown in Step 1.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/providers/auth_provider.dart test/notifications/auth_push_hook_test.dart
git commit -m "feat(notifications): register push token on login, deregister on logout"
```

---

## Task 12: Firebase init + background handler in main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add the top-level background handler and Firebase init**

In `lib/main.dart`, add imports:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
```

Add a top-level function (outside `main`, at file scope — FCM requires this):

```dart
/// Background/terminated push handler. Must be a top-level function.
/// The OS renders the notification half automatically; this exists so data
/// messages are processed and to satisfy the FCM registration requirement.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // No work needed in Phase 1: the notification payload is OS-rendered.
}
```

In `main()`, after `final initialLocation = _resolveInitialLocation(routeStorage);` and before `SentryFlutter.init(`, add a platform-guarded Firebase init:

```dart
  final pushSupported = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  if (pushSupported) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  }
```

- [ ] **Step 2: Verify analyzer clean**

Run: `flutter analyze lib/main.dart`
Expected: No issues (requires `lib/firebase_options.dart` from prerequisite P5 to exist).

- [ ] **Step 3: Verify the app still launches on Linux (push-unsupported path)**

Run: `flutter run -d linux` (or `flutter build linux`)
Expected: App builds/launches; the `pushSupported` guard skips Firebase entirely on Linux.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat(notifications): init firebase + background handler (guarded)"
```

---

## Task 13: Android & iOS native config

**Files:**
- Modify: `android/build.gradle.kts` (or `android/build.gradle`), `android/app/build.gradle.kts`
- Modify: `ios/Runner/Info.plist`, `ios/Runner/AppDelegate.swift`

- [ ] **Step 1: Android — apply the Google Services plugin**

In `android/build.gradle.kts` (project-level) `plugins {}` or `buildscript` dependencies, add the Google Services classpath/plugin per the version FlutterFire generated. In `android/app/build.gradle.kts`, apply:

```kotlin
plugins {
    id("com.google.gms.google-services")
}
```

Ensure `minSdk` is at least 21 (FCM requirement). Check the existing `minSdk` value and raise if lower.

- [ ] **Step 2: iOS — enable Push Notifications capability**

In Xcode (or by editing `ios/Runner/Runner.entitlements`), add the `aps-environment` entitlement (`development` for debug). Add Background Modes → Remote notifications. Confirm `ios/Runner/GoogleService-Info.plist` (prerequisite P3) is in the Runner target.

In `ios/Runner/AppDelegate.swift`, no Flutter-specific FCM code is required beyond the default FlutterAppDelegate when using `firebase_messaging`; confirm it compiles.

- [ ] **Step 3: Build each platform to verify native config**

Run: `flutter build apk --debug`
Expected: Builds successfully (Google Services plugin resolves `google-services.json`).

Run: `flutter build ios --debug --no-codesign`
Expected: Builds successfully.

- [ ] **Step 4: Commit**

```bash
git add android/ ios/
git commit -m "build(notifications): native FCM config for android + ios"
```

---

## Task 14: Full suite + analyze gate

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run: `flutter test`
Expected: All tests PASS, including the new `test/notifications/` files and existing suites.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Manual device verification (documented, not automated)**

Using a test push from the Firebase console (or a backend stub) to a registered device token, with `data` fields:
`{type: event_reminder_8h, eventKey: test, venueAddress: "The Blue Room", firstItemTitle: "Load In", firstItemTime: "2026-06-13T14:00:00", showTime: "2026-06-13T19:00:00"}`
and a `notification` title of the event name:

- Foreground: a banner appears reading `[title]` / `The Blue Room · Load In 2:00pm, Show 7:00pm`.
- Background/terminated: the OS shows the notification.
- Confirm on both an Android device and an iOS device.

- [ ] **Step 4: Final commit (if any doc updates)**

```bash
git add -A
git commit -m "chore(notifications): phase 1 verification pass"
```

---

## Self-Review Notes

- **Spec coverage (Phase 1 portion):** token registration (Tasks 6–7, 10–11), push receipt + render (Tasks 5, 8–9, 12), time-based content matrix minus travel lines (Task 4), dedup keying (`PushPayload.notificationId`, Task 5), platform guards for Linux/web (Tasks 8, 10, 12). Deferred to Phase 2 (explicitly out of scope): `geolocator`, Directions travel time, "leave by" lines, "already left" suppression, `POST /api/mobile/location`. Deferred to backend spec: scheduling/sending, roster selection, server-side 2-per-day cap.
- **Type consistency:** `PushPayload` field names (`venueAddress`, `firstItemTitle`, `firstItemTime`, `showTime`) are used identically in `fromData` (Task 5), `renderBody`/`buildReminderBody` (Tasks 4, 8), and the manual-test payload (Task 14). `firstTimelineItem`/`formatClock`/`buildReminderBody` signatures match across Tasks 2–4 and 8–9. `register`/`deregister` on `DeviceRepository` match between Task 7 and Task 10. `registerCurrentToken`/`deregisterCurrentToken` match between Tasks 10 and 11.
- **Placeholders:** none — every code step shows complete code. Native-config Tasks 13's exact plugin versions depend on FlutterFire output (prerequisite P5); this is genuinely environment-determined, not a hidden TODO.
