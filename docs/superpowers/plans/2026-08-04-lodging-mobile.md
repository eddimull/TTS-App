# Lodging Domain — Mobile Implementation Plan (tts_bandmate repo)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `features/lodging/` vertical slice — list/detail/edit screens, image attachments, maps navigation, Operations-tab entry, and lodging cards on event/booking detail — consuming the backend from `2026-08-04-lodging-backend.md`.

**Architecture:** Hand-written models + Dio repository + Riverpod (`AsyncNotifierProvider.family` list, `FutureProvider.family` detail); shared maps-launch helper extracted from the two duplicated call sites; attachment display via promoted shared widgets (`AuthThumbnail` already shared; lightbox/url helpers promoted from the events feature).

**Tech Stack:** Flutter/Dart, Cupertino, Riverpod v2, Dio, GoRouter, image_picker, url_launcher, intl.

**Repo:** `/home/eddie/github/tts_bandmate` — fresh branch `feat/lodging` off up-to-date `main`. PR base `main`. **Backend PR must be merged + deployed to staging first.**

## Global Constraints

- Cupertino widgets; text colors via `context.secondaryText` etc. (`package:tts_bandmate/core/theme/context_colors.dart`) — never raw `CupertinoColors.secondaryLabel` in a `color:`.
- UI must work at 320pt width (narrow iPhone) — long hotel names/addresses must wrap or ellipsize.
- Response envelopes: named keys, no `data` wrapper. Datetimes on the wire: `Y-m-d H:i:s` strings; keep raw strings on models with parsed getters.
- Test dates computed relative to `DateTime.now()` — never hardcoded.
- `flutter analyze` clean and `flutter test` green before every commit.
- Conventional commits; the final `feat:` merge triggers release-please's 1.23.0 PR automatically — do NOT bump `pubspec.yaml` manually.
- New abilities sharp edge: tokens issued before the backend deploy lack `read:lodging`. The ApiClient already auto-refreshes on the specific 403 `{"message": "Insufficient token permissions."}` (`api_client.dart:80-94`). On any *other* lodging-list 403, hide the feature (show empty/absent), never an error banner. Local testing requires re-login.

---

### Task 1: Shared maps-launch helper (refactor)

**Files:**
- Create: `lib/shared/utils/maps_launch.dart`
- Modify: `lib/features/events/screens/event_edit_screen.dart:1351-1369` (`_openVenueInMapsFromEdit`)
- Modify: `lib/features/bookings/widgets/event_sub_form_card.dart:530-549` (`_openInMaps`)
- Test: `test/shared/utils/maps_launch_test.dart`

**Interfaces:**
- Produces: `Uri? mapsSearchUri({double? lat, double? lng, String? address, String? name})` (pure, testable) and `Future<void> openInMaps({double? lat, double? lng, String? address, String? name})` (launches). Precedence: lat/lng → address → name → no-op.

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/utils/maps_launch_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/utils/maps_launch.dart';

void main() {
  group('mapsSearchUri', () {
    test('prefers coordinates over address and name', () {
      final uri = mapsSearchUri(
          lat: 30.4, lng: -91.1, address: '123 Main St', name: 'Hotel');
      expect(uri.toString(), 'https://maps.google.com/?q=30.4,-91.1');
    });

    test('falls back to encoded address', () {
      final uri = mapsSearchUri(address: '123 Main St', name: 'Hotel');
      expect(uri.toString(), 'https://maps.google.com/?q=123%20Main%20St');
    });

    test('falls back to encoded name', () {
      final uri = mapsSearchUri(name: 'Hampton Inn');
      expect(uri.toString(), 'https://maps.google.com/?q=Hampton%20Inn');
    });

    test('returns null when nothing is provided', () {
      expect(mapsSearchUri(), isNull);
      expect(mapsSearchUri(address: '', name: ''), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/utils/maps_launch_test.dart`
Expected: FAIL — file doesn't exist

- [ ] **Step 3: Write the helper**

```dart
// lib/shared/utils/maps_launch.dart
import 'package:url_launcher/url_launcher.dart';

/// Builds a Google Maps search URI for a place.
///
/// Precedence: coordinates → address → name. Returns null when nothing
/// usable is provided. Google Maps URLs open the native app on iOS and
/// Android and the browser elsewhere.
Uri? mapsSearchUri({double? lat, double? lng, String? address, String? name}) {
  if (lat != null && lng != null) {
    return Uri.parse('https://maps.google.com/?q=$lat,$lng');
  }
  if (address != null && address.isNotEmpty) {
    return Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(address)}');
  }
  if (name != null && name.isNotEmpty) {
    return Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(name)}');
  }
  return null;
}

/// Launches maps for the given place; silent no-op when unresolvable.
Future<void> openInMaps(
    {double? lat, double? lng, String? address, String? name}) async {
  final uri = mapsSearchUri(lat: lat, lng: lng, address: address, name: name);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
```

- [ ] **Step 4: Refactor both call sites**

`event_edit_screen.dart` — replace the body of `_openVenueInMapsFromEdit` with:
```dart
  Future<void> _openVenueInMapsFromEdit() => openInMaps(
        lat: _venueLat,
        lng: _venueLng,
        address: _venueAddress,
        name: _venueName,
      );
```
`event_sub_form_card.dart` — replace the body of `_openInMaps` with:
```dart
  Future<void> _openInMaps() => openInMaps(
        lat: _venueLat,
        lng: _venueLng,
        address: widget.draft.venueAddress ?? '',
        name: widget.draft.venueName ?? '',
      );
```
Add `import 'package:tts_bandmate/shared/utils/maps_launch.dart';` to both (match the import style — relative vs package — used by neighbouring imports in each file). Remove the now-unused `url_launcher` import from either file ONLY if nothing else in it uses `launchUrl` (event_edit_screen also launches other URLs — check first).

Note the local method in `event_sub_form_card.dart` shadows the helper name; rename the local method to `_openVenueInMaps` if the analyzer complains about recursion — verify it resolves to the top-level function or rename the import with `as maps`.

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/shared/utils/maps_launch_test.dart && flutter analyze`
Expected: PASS, no new analyzer issues

- [ ] **Step 6: Commit**

```bash
git add lib test
git commit -m "refactor: extract shared maps-launch helper from event edit + sub form card"
```

---

### Task 2: Models + endpoints + repository

**Files:**
- Create: `lib/features/lodging/data/models/lodging.dart`
- Create: `lib/features/lodging/data/lodging_repository.dart`
- Modify: `lib/core/network/api_endpoints.dart` (new Lodging section)
- Test: `test/features/lodging/lodging_models_test.dart`, `test/features/lodging/lodging_repository_test.dart`

**Interfaces:**
- Consumes backend wire contract (see `2026-08-04-lodging-backend.md` Task 2): list `{"lodgings": [...], "can_write": bool}`, detail `{"lodging": {...}, "can_write": bool}`, mutations return `{"lodging": {...}}`, upload returns `{"attachment": {...}}` at 201.
- Produces:
  - `Lodging` (detail: id, name, address?, latitude?, longitude?, checkInAt, checkOutAt, notes?, booking?, event?, rooms, attachments), `LodgingSummary` (list item: id, name, address?, checkInAt, checkOutAt, roomCount, attachmentCount, bookingId?, eventId?), `LodgingRoom` (id?, label, confirmationNumber?, notes?), `LodgingAttachment` (id, filename, mimeType, fileSize, url), `LodgingLinkedBooking` (id, name), `LodgingLinkedEvent` (id, title, date).
  - `LodgingRepository`: `Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(int bandId)`, `Future<({Lodging lodging, bool canWrite})> getLodging(int bandId, int lodgingId)`, `Future<Lodging> createLodging(int bandId, {required String name, String? address, double? latitude, double? longitude, required String checkInAt, required String checkOutAt, String? notes, int? bookingId, int? eventId, List<LodgingRoom> rooms})`, `Future<Lodging> updateLodging(int bandId, int lodgingId, Map<String, dynamic> patch)`, `Future<void> deleteLodging(int bandId, int lodgingId)`, `Future<LodgingAttachment> uploadAttachment(int bandId, int lodgingId, {required List<int> bytes, required String filename})`, `Future<void> deleteAttachment(int bandId, int lodgingId, int attachmentId)`.
  - `lodgingRepositoryProvider` at the bottom of the repository file.

- [ ] **Step 1: Write failing model tests**

```dart
// test/features/lodging/lodging_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';

void main() {
  group('Lodging.fromJson', () {
    test('parses full payload', () {
      final json = {
        'id': 1,
        'name': 'Hampton Inn',
        'address': '123 Main St',
        'latitude': 30.4,
        'longitude': -91.1,
        'check_in_at': '2030-08-14 15:00:00',
        'check_out_at': '2030-08-16 11:00:00',
        'notes': 'Park in back',
        'booking': {'id': 5, 'name': 'Smith Wedding'},
        'event': {'id': 9, 'title': 'Reception', 'date': '2030-08-15'},
        'rooms': [
          {'id': 1, 'label': 'King', 'confirmation_number': 'ABC123', 'notes': null, 'sort_order': 0},
        ],
        'attachments': [
          {'id': 2, 'filename': 'map.jpg', 'mime_type': 'image/jpeg', 'file_size': 1234, 'url': 'https://x/api/mobile/lodging-attachments/2'},
        ],
      };

      final lodging = Lodging.fromJson(json);
      expect(lodging.id, 1);
      expect(lodging.name, 'Hampton Inn');
      expect(lodging.latitude, 30.4);
      expect(lodging.checkInAt, '2030-08-14 15:00:00');
      expect(lodging.parsedCheckIn.hour, 15);
      expect(lodging.booking!.name, 'Smith Wedding');
      expect(lodging.event!.title, 'Reception');
      expect(lodging.rooms.single.confirmationNumber, 'ABC123');
      expect(lodging.attachments.single.mimeType, 'image/jpeg');
    });

    test('tolerates missing optionals and malformed lists', () {
      final lodging = Lodging.fromJson({
        'id': 2,
        'name': 'Bare',
        'check_in_at': '2030-01-01 15:00:00',
        'check_out_at': '2030-01-02 11:00:00',
        'rooms': 'not-a-list',
      });
      expect(lodging.address, isNull);
      expect(lodging.booking, isNull);
      expect(lodging.rooms, isEmpty);
      expect(lodging.attachments, isEmpty);
    });
  });

  group('LodgingSummary.fromJson', () {
    test('parses counts and link ids', () {
      final s = LodgingSummary.fromJson({
        'id': 3,
        'name': 'Listed',
        'address': null,
        'check_in_at': '2030-02-01 15:00:00',
        'check_out_at': '2030-02-02 11:00:00',
        'room_count': 3,
        'attachment_count': 1,
        'booking_id': 7,
        'event_id': null,
      });
      expect(s.roomCount, 3);
      expect(s.bookingId, 7);
      expect(s.eventId, isNull);
    });
  });

  group('LodgingRoom.toJson', () {
    test('includes id only when set', () {
      expect(const LodgingRoom(label: 'King').toJson(), {'label': 'King'});
      expect(
        const LodgingRoom(id: 4, label: 'King', confirmationNumber: 'A1').toJson(),
        {'id': 4, 'label': 'King', 'confirmation_number': 'A1'},
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/lodging/lodging_models_test.dart`
Expected: FAIL — file doesn't exist

- [ ] **Step 3: Write the models** (conventions from `rehearsal_detail.dart`: const constructors, `(json['id'] as num).toInt()`, raw ISO strings + parsed getters, `is List` guards, sub-models in the same file)

```dart
// lib/features/lodging/data/models/lodging.dart

class LodgingLinkedBooking {
  const LodgingLinkedBooking({required this.id, required this.name});
  final int id;
  final String name;

  factory LodgingLinkedBooking.fromJson(Map<String, dynamic> json) =>
      LodgingLinkedBooking(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
      );
}

class LodgingLinkedEvent {
  const LodgingLinkedEvent({required this.id, required this.title, this.date});
  final int id;
  final String title;
  final String? date;

  factory LodgingLinkedEvent.fromJson(Map<String, dynamic> json) =>
      LodgingLinkedEvent(
        id: (json['id'] as num).toInt(),
        title: json['title'] as String? ?? '',
        date: json['date'] as String?,
      );
}

class LodgingRoom {
  const LodgingRoom({
    this.id,
    required this.label,
    this.confirmationNumber,
    this.notes,
  });

  final int? id;
  final String label;
  final String? confirmationNumber;
  final String? notes;

  factory LodgingRoom.fromJson(Map<String, dynamic> json) => LodgingRoom(
        id: (json['id'] as num?)?.toInt(),
        label: json['label'] as String? ?? '',
        confirmationNumber: json['confirmation_number'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'label': label,
        if (confirmationNumber != null) 'confirmation_number': confirmationNumber,
        if (notes != null) 'notes': notes,
      };
}

class LodgingAttachment {
  const LodgingAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    required this.url,
  });

  final int id;
  final String filename;
  final String mimeType;
  final int fileSize;
  final String url;

  factory LodgingAttachment.fromJson(Map<String, dynamic> json) =>
      LodgingAttachment(
        id: (json['id'] as num).toInt(),
        filename: json['filename'] as String? ?? '',
        mimeType: json['mime_type'] as String? ?? '',
        fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
        url: json['url'] as String? ?? '',
      );
}

class LodgingSummary {
  const LodgingSummary({
    required this.id,
    required this.name,
    this.address,
    required this.checkInAt,
    required this.checkOutAt,
    required this.roomCount,
    required this.attachmentCount,
    this.bookingId,
    this.eventId,
  });

  final int id;
  final String name;
  final String? address;
  final String checkInAt;
  final String checkOutAt;
  final int roomCount;
  final int attachmentCount;
  final int? bookingId;
  final int? eventId;

  factory LodgingSummary.fromJson(Map<String, dynamic> json) => LodgingSummary(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        address: json['address'] as String?,
        checkInAt: json['check_in_at'] as String? ?? '',
        checkOutAt: json['check_out_at'] as String? ?? '',
        roomCount: (json['room_count'] as num?)?.toInt() ?? 0,
        attachmentCount: (json['attachment_count'] as num?)?.toInt() ?? 0,
        bookingId: (json['booking_id'] as num?)?.toInt(),
        eventId: (json['event_id'] as num?)?.toInt(),
      );

  /// Parses [checkInAt]; falls back to now on malformed input.
  DateTime get parsedCheckIn =>
      DateTime.tryParse(checkInAt) ?? DateTime.now();
}

class Lodging {
  const Lodging({
    required this.id,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    required this.checkInAt,
    required this.checkOutAt,
    this.notes,
    this.booking,
    this.event,
    required this.rooms,
    required this.attachments,
  });

  final int id;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String checkInAt;
  final String checkOutAt;
  final String? notes;
  final LodgingLinkedBooking? booking;
  final LodgingLinkedEvent? event;
  final List<LodgingRoom> rooms;
  final List<LodgingAttachment> attachments;

  factory Lodging.fromJson(Map<String, dynamic> json) {
    final rawRooms = json['rooms'];
    final rawAttachments = json['attachments'];
    return Lodging(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      checkInAt: json['check_in_at'] as String? ?? '',
      checkOutAt: json['check_out_at'] as String? ?? '',
      notes: json['notes'] as String?,
      booking: json['booking'] is Map<String, dynamic>
          ? LodgingLinkedBooking.fromJson(json['booking'] as Map<String, dynamic>)
          : null,
      event: json['event'] is Map<String, dynamic>
          ? LodgingLinkedEvent.fromJson(json['event'] as Map<String, dynamic>)
          : null,
      rooms: rawRooms is List
          ? rawRooms.cast<Map<String, dynamic>>().map(LodgingRoom.fromJson).toList()
          : const [],
      attachments: rawAttachments is List
          ? rawAttachments
              .cast<Map<String, dynamic>>()
              .map(LodgingAttachment.fromJson)
              .toList()
          : const [],
    );
  }

  DateTime get parsedCheckIn => DateTime.tryParse(checkInAt) ?? DateTime.now();
  DateTime get parsedCheckOut => DateTime.tryParse(checkOutAt) ?? DateTime.now();

  @override
  bool operator ==(Object other) => other is Lodging && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
```

- [ ] **Step 4: Endpoints.** In `api_endpoints.dart` add a section (style of `:203-208`):

```dart
  // ── Lodging ─────────────────────────────────────────────────────────
  static String mobileBandLodgings(int bandId) =>
      '/api/mobile/bands/$bandId/lodgings';
  static String mobileBandLodging(int bandId, int lodgingId) =>
      '/api/mobile/bands/$bandId/lodgings/$lodgingId';
  static String mobileLodgingAttachments(int bandId, int lodgingId) =>
      '/api/mobile/bands/$bandId/lodgings/$lodgingId/attachments';
  static String mobileLodgingAttachment(
          int bandId, int lodgingId, int attachmentId) =>
      '/api/mobile/bands/$bandId/lodgings/$lodgingId/attachments/$attachmentId';
```

- [ ] **Step 5: Write failing repository tests** (using the `_FakeAdapter` pattern from `test/features/rehearsals/rehearsals_repository_test.dart:9-29` — copy that adapter class into this file)

```dart
// test/features/lodging/lodging_repository_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responseBody, {this.statusCode = 200});

  final Map<String, dynamic> responseBody;
  final int statusCode;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

LodgingRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
  return LodgingRepository(dio);
}

void main() {
  test('getLodgings hits band-scoped endpoint and parses envelope', () async {
    final adapter = _FakeAdapter({
      'lodgings': [
        {
          'id': 1,
          'name': 'Hampton Inn',
          'check_in_at': '2030-08-14 15:00:00',
          'check_out_at': '2030-08-16 11:00:00',
          'room_count': 2,
          'attachment_count': 0,
        },
      ],
      'can_write': true,
    });

    final result = await _repo(adapter).getLodgings(7);

    expect(adapter.lastRequest!.path, '/api/mobile/bands/7/lodgings');
    expect(result.lodgings.single.name, 'Hampton Inn');
    expect(result.canWrite, isTrue);
  });

  test('createLodging posts payload with rooms', () async {
    final adapter = _FakeAdapter({
      'lodging': {
        'id': 9,
        'name': 'New Hotel',
        'check_in_at': '2030-08-14 15:00:00',
        'check_out_at': '2030-08-16 11:00:00',
        'rooms': [],
        'attachments': [],
      },
    });

    final lodging = await _repo(adapter).createLodging(
      7,
      name: 'New Hotel',
      checkInAt: '2030-08-14 15:00:00',
      checkOutAt: '2030-08-16 11:00:00',
      rooms: const [LodgingRoom(label: 'King')],
    );

    expect(adapter.lastRequest!.method, 'POST');
    final sent = adapter.lastRequest!.data as Map<String, dynamic>;
    expect(sent['name'], 'New Hotel');
    expect(sent['rooms'], [
      {'label': 'King'}
    ]);
    expect(lodging.id, 9);
  });

  test('updateLodging patches only the given fields', () async {
    final adapter = _FakeAdapter({
      'lodging': {
        'id': 9,
        'name': 'Renamed',
        'check_in_at': '2030-08-14 15:00:00',
        'check_out_at': '2030-08-16 11:00:00',
        'rooms': [],
        'attachments': [],
      },
    });

    await _repo(adapter).updateLodging(7, 9, {'name': 'Renamed'});

    expect(adapter.lastRequest!.method, 'PATCH');
    expect(adapter.lastRequest!.path, '/api/mobile/bands/7/lodgings/9');
    expect(adapter.lastRequest!.data, {'name': 'Renamed'});
  });

  test('uploadAttachment posts multipart file', () async {
    final adapter = _FakeAdapter({
      'attachment': {
        'id': 3,
        'filename': 'map.jpg',
        'mime_type': 'image/jpeg',
        'file_size': 5,
        'url': 'http://x/api/mobile/lodging-attachments/3',
      },
    }, statusCode: 201);

    final attachment = await _repo(adapter).uploadAttachment(
      7,
      9,
      bytes: [1, 2, 3, 4, 5],
      filename: 'map.jpg',
    );

    expect(adapter.lastRequest!.data, isA<FormData>());
    expect(attachment.id, 3);
  });
}
```

- [ ] **Step 6: Write the repository**

```dart
// lib/features/lodging/data/lodging_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/lodging.dart';

class LodgingRepository {
  LodgingRepository(this._dio);

  final Dio _dio;

  Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(
      int bandId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodgings(bandId),
    );
    final data = response.data!;
    final raw = data['lodgings'];
    final lodgings = raw is List
        ? raw.cast<Map<String, dynamic>>().map(LodgingSummary.fromJson).toList()
        : <LodgingSummary>[];
    return (lodgings: lodgings, canWrite: data['can_write'] as bool? ?? false);
  }

  Future<({Lodging lodging, bool canWrite})> getLodging(
      int bandId, int lodgingId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodging(bandId, lodgingId),
    );
    final data = response.data!;
    return (
      lodging: Lodging.fromJson(data['lodging'] as Map<String, dynamic>),
      canWrite: data['can_write'] as bool? ?? false,
    );
  }

  Future<Lodging> createLodging(
    int bandId, {
    required String name,
    String? address,
    double? latitude,
    double? longitude,
    required String checkInAt,
    required String checkOutAt,
    String? notes,
    int? bookingId,
    int? eventId,
    List<LodgingRoom> rooms = const [],
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodgings(bandId),
      data: {
        'name': name,
        if (address != null) 'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'check_in_at': checkInAt,
        'check_out_at': checkOutAt,
        if (notes != null) 'notes': notes,
        if (bookingId != null) 'booking_id': bookingId,
        if (eventId != null) 'event_id': eventId,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      },
    );
    return Lodging.fromJson(response.data!['lodging'] as Map<String, dynamic>);
  }

  /// PATCH with an explicit field map — callers control exactly which keys
  /// are sent (null values included intentionally clear fields server-side).
  Future<Lodging> updateLodging(
      int bandId, int lodgingId, Map<String, dynamic> patch) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      ApiEndpoints.mobileBandLodging(bandId, lodgingId),
      data: patch,
    );
    return Lodging.fromJson(response.data!['lodging'] as Map<String, dynamic>);
  }

  Future<void> deleteLodging(int bandId, int lodgingId) async {
    await _dio.delete<void>(ApiEndpoints.mobileBandLodging(bandId, lodgingId));
  }

  Future<LodgingAttachment> uploadAttachment(
    int bandId,
    int lodgingId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.mobileLodgingAttachments(bandId, lodgingId),
      data: formData,
    );
    return LodgingAttachment.fromJson(
        response.data!['attachment'] as Map<String, dynamic>);
  }

  Future<void> deleteAttachment(
      int bandId, int lodgingId, int attachmentId) async {
    await _dio.delete<void>(
        ApiEndpoints.mobileLodgingAttachment(bandId, lodgingId, attachmentId));
  }
}

final lodgingRepositoryProvider = Provider<LodgingRepository>((ref) {
  return LodgingRepository(ref.watch(apiClientProvider).dio);
});
```

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/features/lodging/ && flutter analyze`
Expected: PASS (all model + repository tests), analyzer clean

- [ ] **Step 8: Commit**

```bash
git add lib test
git commit -m "feat(lodging): models, endpoints, repository"
```

---

### Task 3: Providers + realtime registry

**Files:**
- Create: `lib/features/lodging/providers/lodging_provider.dart`
- Modify: `lib/shared/providers/band_realtime_provider.dart` (model registry ~line 150 + invalidation switch ~line 83)
- Test: `test/features/lodging/lodging_provider_test.dart`

**Interfaces:**
- Consumes: `LodgingRepository` (Task 2), `selectedBandProvider`.
- Produces:
  - `lodgingsProvider` — `AsyncNotifierProvider.family<LodgingsNotifier, LodgingListState, int>` keyed by bandId, where `LodgingListState` is a record `({List<LodgingSummary> lodgings, bool canWrite})`. Methods: `refresh()`, `remove(int lodgingId)` (optimistic), and it is the invalidation target for realtime + mutations.
  - `lodgingDetailProvider` — `FutureProvider.family<({Lodging lodging, bool canWrite}), int>` keyed by lodgingId (reads bandId from `selectedBandProvider` inside).

- [ ] **Step 1: Write failing provider test** (pattern: `test/features/rehearsals/rehearsals_provider_test.dart` — throwing-Dio subclass fake, `ProviderContainer` with override, `addTearDown(container.dispose)`)

```dart
// test/features/lodging/lodging_provider_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/providers/lodging_provider.dart';

final _throwingDio = Dio();

class _FakeLodgingRepository extends LodgingRepository {
  _FakeLodgingRepository() : super(_throwingDio);

  int listCalls = 0;

  @override
  Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(
      int bandId) async {
    listCalls++;
    return (
      lodgings: [
        LodgingSummary(
          id: 1,
          name: 'Hotel A',
          checkInAt: DateTime.now()
              .add(const Duration(days: 3))
              .toIso8601String(),
          checkOutAt: DateTime.now()
              .add(const Duration(days: 4))
              .toIso8601String(),
          roomCount: 1,
          attachmentCount: 0,
        ),
      ],
      canWrite: true,
    );
  }
}

void main() {
  test('lodgingsProvider loads list and canWrite via repository', () async {
    final repo = _FakeLodgingRepository();
    final container = ProviderContainer(overrides: [
      lodgingRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final state = await container.read(lodgingsProvider(7).future);

    expect(repo.listCalls, 1);
    expect(state.lodgings.single.name, 'Hotel A');
    expect(state.canWrite, isTrue);
  });

  test('remove() drops the entry optimistically', () async {
    final repo = _FakeLodgingRepository();
    final container = ProviderContainer(overrides: [
      lodgingRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(lodgingsProvider(7).future);
    container.read(lodgingsProvider(7).notifier).remove(1);

    final state = container.read(lodgingsProvider(7)).value!;
    expect(state.lodgings, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/lodging/lodging_provider_test.dart`
Expected: FAIL — provider file doesn't exist

- [ ] **Step 3: Write the providers**

```dart
// lib/features/lodging/providers/lodging_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/selected_band_provider.dart';
import '../data/lodging_repository.dart';
import '../data/models/lodging.dart';

typedef LodgingListState = ({List<LodgingSummary> lodgings, bool canWrite});

class LodgingsNotifier extends AsyncNotifier<LodgingListState> {
  LodgingsNotifier(this._bandId);

  final int _bandId;

  LodgingRepository get _repo => ref.read(lodgingRepositoryProvider);

  @override
  Future<LodgingListState> build() => _repo.getLodgings(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getLodgings(_bandId));
  }

  /// Optimistically removes a deleted lodging from the list.
  void remove(int lodgingId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data((
      lodgings: current.lodgings.where((l) => l.id != lodgingId).toList(),
      canWrite: current.canWrite,
    ));
  }
}

final lodgingsProvider =
    AsyncNotifierProvider.family<LodgingsNotifier, LodgingListState, int>(
  (arg) => LodgingsNotifier(arg),
);

final lodgingDetailProvider =
    FutureProvider.family<({Lodging lodging, bool canWrite}), int>(
        (ref, lodgingId) async {
  final bandId = ref.watch(selectedBandProvider).value;
  if (bandId == null) {
    throw StateError('No band selected');
  }
  return ref.watch(lodgingRepositoryProvider).getLodging(bandId, lodgingId);
});
```

Check `selectedBandProvider`'s actual value shape (`lib/shared/providers/selected_band_provider.dart`) — if it exposes the id differently (e.g. `.value` is a band object), adapt the two lines that read it (also used in screens).

- [ ] **Step 4: Realtime registry.** In `lib/shared/providers/band_realtime_provider.dart`:
  - Add `'lodging'` to the known-models list (~line 150).
  - Add a case in the invalidation switch (~line 83) mirroring `case 'rehearsal':`:
```dart
      case 'lodging':
        ref.invalidate(lodgingsProvider(bandId));
        if (id != null) ref.invalidate(lodgingDetailProvider(id));
        break;
```
Match the switch's actual variable names — read the surrounding cases first and copy their exact style (some cases may only have access to certain fields; wire model name from the backend is `lodging` = `Str::snake(class_basename(Lodging::class))`).

- [ ] **Step 5: Run tests + analyze, commit**

Run: `flutter test test/features/lodging/ && flutter analyze`
Expected: PASS

```bash
git add lib test
git commit -m "feat(lodging): riverpod providers + realtime invalidation"
```

---

### Task 4: List + detail screens, routes, Operations entry

**Files:**
- Create: `lib/features/lodging/screens/lodging_list_screen.dart`
- Create: `lib/features/lodging/screens/lodging_detail_screen.dart`
- Create: `lib/shared/widgets/attachment_widgets.dart` (promoted from `lib/features/events/screens/attachment_widgets.dart`)
- Modify: `lib/features/events/screens/attachment_widgets.dart` → delete after re-pointing imports (grep `attachment_widgets` across `lib/`)
- Modify: `lib/core/config/router.dart` (routes outside the shell, next to the media/rehearsals block ~line 463-499)
- Modify: `lib/features/more/screens/operations_screen.dart` (NavRow after Personnel)
- Test: `test/features/lodging/lodging_list_widget_test.dart`

**Interfaces:**
- Consumes: `lodgingsProvider`, `lodgingDetailProvider`, `openInMaps` (Task 1), `AuthThumbnail` (`lib/shared/widgets/auth_thumbnail.dart`), promoted `resolveAttachmentUrl`/`attachmentIcon`/`AttachmentLightbox`.
- Produces: routes `/lodging` (list), `/lodging/:id` (detail); Operations-tab entry. Detail screen exposes an Edit button (wired in Task 5 to `/lodging/:id/edit`).

- [ ] **Step 1: Promote attachment widgets.** Move `resolveAttachmentUrl`, `attachmentIcon`, `fetchImageBytes`, and `AttachmentLightbox` from `lib/features/events/screens/attachment_widgets.dart` to `lib/shared/widgets/attachment_widgets.dart` unchanged EXCEPT: drop the debug `print` inside the assert block (`attachment_widgets.dart:16-20`). `AttachmentLightbox` is typed against the events `EventAttachment` model — check its actual field usage (likely `url`/`mimeType`/`filename`); if so, refactor it to accept a small interface-like record list `List<({String url, String filename})>` OR keep it generic by having both `EventAttachment` and `LodgingAttachment` satisfy the same signature via an abstract class `DisplayableAttachment { String get url; String get mimeType; String get filename; int get id; }` implemented by both models. Choose whichever needs the fewest edits after reading the file; update all importers (`event_detail_screen.dart` etc.) and run `flutter analyze` until clean.

- [ ] **Step 2: Routes.** In `router.dart`, next to the `/media` route (outside the shell), literal segments before `:param`:

```dart
      // Lodging — no bottom nav, pushed from Operations screen
      GoRoute(
        path: '/lodging',
        builder: (_, __) => const LodgingListScreen(),
      ),
      GoRoute(
        path: '/lodging/new',
        builder: (_, __) => const LodgingEditScreen(lodgingId: null),
      ),
      GoRoute(
        path: '/lodging/:id/edit',
        builder: (_, state) => LodgingEditScreen(
          lodgingId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/lodging/:id',
        builder: (_, state) => LodgingDetailScreen(
          lodgingId: int.parse(state.pathParameters['id']!),
        ),
      ),
```
(`LodgingEditScreen` arrives in Task 5 — add its two routes in that task if you prefer strictly compiling commits; otherwise stub the screen first.) Also check the route-allowlist constant at `router.dart:~95-105` (contains `'/personnel'`) and add `'/lodging'` if the list gates pushed routes.

- [ ] **Step 3: Operations entry.** In `operations_screen.dart` after the Personnel row (`:54-60`), NOT gated on `isOwner` (members read lodging):

```dart
          NavRow(
            title: 'Lodging',
            leading: Icon(CupertinoIcons.bed_double,
                size: 22, color: context.secondaryText),
            onTap: () => context.push('/lodging'),
          ),
```

- [ ] **Step 4: List screen.** `ConsumerWidget` + `CupertinoPageScaffold` + `CustomScrollView` with `CupertinoSliverNavigationBar(largeTitle: Text('Lodging'))` and `CupertinoSliverRefreshControl(onRefresh: () async => ref.invalidate(lodgingsProvider(bandId)))`. Structure:

```dart
class LodgingListScreen extends ConsumerWidget {
  const LodgingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;
    if (bandId == null) {
      return const CupertinoPageScaffold(
          child: Center(child: CupertinoActivityIndicator()));
    }
    final async = ref.watch(lodgingsProvider(bandId));
    // async.when(...) → loading spinner / error state / list
  }
}
```

Behaviors:
- **Split upcoming vs past** on `parsedCheckOut.isAfter(DateTime.now())`; upcoming ascending by check-in at top; past under a "Past stays" `_SectionHeader`, collapsed behind a "Show N past stays" `CupertinoButton` toggle (local `StatefulWidget` bool or a simple `StateProvider`).
- Row content: name (bold, `context.primaryText`, maxLines 2, ellipsis), `DateFormat('EEEE, MMMM d')` check-in – check-out range + times, room count caption (`context.secondaryText`), chevron. Tap → `context.push('/lodging/${l.id}')`.
- `canWrite` → trailing nav-bar `CupertinoButton(child: Icon(CupertinoIcons.add), onPressed: () => context.push('/lodging/new'))`.
- **403 = hidden**: on error, if it's a `DioException` with `response?.statusCode == 403`, render the empty state ("No lodging yet") with no error banner; other errors get the standard retry state used by `rehearsals_screen.dart:75` (`onRetry: () => ref.invalidate(...)`).
- Empty state: centered `bed_double` icon + "No lodging yet" + (if canWrite) an "Add lodging" button.

- [ ] **Step 5: Detail screen.** `ConsumerWidget` watching `lodgingDetailProvider(lodgingId)`. Sections (each a card-style container like the event detail screen):
  - Name + check-in/check-out: `DateFormat('EEEE, MMMM d, yyyy')` + `DateFormat('h:mm a')` on `parsedCheckIn`/`parsedCheckOut` ("Check-in  Fri, August 14 · 3:00 PM" rows).
  - Address row (when `address` non-null/non-empty): tappable, trailing `CupertinoIcons.map`, `onTap: () => openInMaps(lat: lodging.latitude, lng: lodging.longitude, address: lodging.address, name: lodging.name)`.
  - Rooms: one row per room — label bold, confirmation number in monospace-ish secondary text ("conf# ABC123"), notes caption below; separator lines `CupertinoColors.separator.resolveFrom(context)`.
  - Notes: plain text section when non-empty.
  - Attachments: reuse the `_AttachmentsSection` approach from `event_detail_screen.dart:1618-1694` — image thumbnails via `AuthThumbnail`, tap → `AttachmentLightbox`, non-images → `launchUrl`. When `canWrite`, an "Add photo" button opens the image picker (`ImagePicker().pickMultiImage(imageQuality: 100)`), uploads each via `repo.uploadAttachment(bandId, lodgingId, bytes: await File(path).readAsBytes(), filename: basename(path))`, then `ref.invalidate(lodgingDetailProvider(lodgingId))`. Long-press (or trailing delete icon in edit-capable state) → confirm dialog → `deleteAttachment` + invalidate.
  - Linked booking/event: `NavRow`-style rows → `context.push('/bookings/${booking.id}')` / event detail route (grep `router.dart` for the event-detail path — events route by key, so the backend `event` link payload may need the event `key`; if only `id` is available, link just the booking and show event title as plain text — note this in code).
  - `canWrite` → nav bar trailing "Edit" → `context.push('/lodging/$lodgingId/edit')`.
  - Delete lives on the edit screen (Task 5).

Popup sheets on this screen must re-attach the provider scope (`UncontrolledProviderScope(container: ProviderScope.containerOf(context), ...)`) — copy the pattern at `event_detail_screen.dart:1408-1418`.

- [ ] **Step 6: Widget test**

```dart
// test/features/lodging/lodging_list_widget_test.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/screens/lodging_list_screen.dart';

// Reuse/copy the fake repository from lodging_provider_test.dart and a fake
// selectedBandProvider override; see test/helpers/test_harness.dart for the
// established override style.

void main() {
  testWidgets('shows upcoming stay name and hides past by default at 320pt',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Fake repo returns one upcoming ('Upcoming Hotel', check-in now+3d)
    // and one past ('Past Hotel', check-out now-2d) stay, canWrite=false.
    await tester.pumpWidget(ProviderScope(
      overrides: [/* lodgingRepositoryProvider + selectedBandProvider */],
      child: const CupertinoApp(home: LodgingListScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Upcoming Hotel'), findsOneWidget);
    expect(find.text('Past Hotel'), findsNothing);
    expect(find.textContaining('past stay'), findsOneWidget); // toggle label
  });
}
```
Fill in the overrides concretely: `lodgingRepositoryProvider.overrideWithValue(fakeRepo)` and override `selectedBandProvider` the way `test/helpers/test_harness.dart` / existing widget tests do (grep `selectedBandProvider.overrideWith` in `test/` and copy). Compute the two stays' dates relative to `DateTime.now()`.

- [ ] **Step 7: Run + analyze + commit**

Run: `flutter test && flutter analyze`
Expected: PASS, clean (full suite — the attachment-widget promotion touched events code)

```bash
git add lib test
git commit -m "feat(lodging): list/detail screens, routes, operations entry, shared attachment widgets"
```

---

### Task 5: Edit screen (create + edit + delete)

**Files:**
- Create: `lib/features/lodging/screens/lodging_edit_screen.dart`
- Modify: `lib/core/config/router.dart` (only if the `/lodging/new` + `/lodging/:id/edit` routes were deferred in Task 4)
- Test: extend `test/features/lodging/lodging_provider_test.dart` with create/update paths if notifier gains methods (mutations may call the repository directly from the screen like rehearsals does — prefer that; then no new provider tests needed)

**Interfaces:**
- Consumes: `LodgingRepository`, `lodgingDetailProvider` (prefill), `lodgingsProvider` (invalidation), `AddressAutocompleteField` (`lib/shared/widgets/address_autocomplete_field.dart` — writes street into the controller, gives city/state/zip via `onResolved`; NO lat/lng), `geocoding` helper (`lib/core/network/geocoding.dart`) to resolve lat/lng from the final address string.
- Produces: `LodgingEditScreen({required int? lodgingId})` — `lodgingId == null` → create mode.

- [ ] **Step 1: Screen skeleton.** `ConsumerStatefulWidget`. In edit mode, read the existing detail via `ref.read(lodgingDetailProvider(lodgingId).future)` in `initState`-triggered load (or watch and build the form when loaded). Controllers/state:
  - `_nameController`, `_addressController`, `_notesController`
  - `DateTime? _checkIn`, `DateTime? _checkOut`
  - `double? _lat`, `_lng`
  - `List<_RoomDraft>` (`{int? id, TextEditingController label, TextEditingController confirmation, TextEditingController notes}`)
  - `int? _bookingId`, `int? _eventId`
- [ ] **Step 2: Fields.**
  - Name: `CupertinoTextField` with label (copy the field row style used by `event_edit_screen.dart` forms).
  - Address: `AddressAutocompleteField(label: 'Address', controller: _addressController, onResolved: (components) { ... compose full address into controller ... })`. After resolve OR on save with a non-empty address and null `_lat`, geocode via the existing helper in `lib/core/network/geocoding.dart` (read its API first — it exposes a geocode-by-address call used by `band_info_edit_screen.dart:56`) to populate `_lat`/`_lng`. Failure to geocode is non-fatal (maps falls back to address string).
  - Check-in / check-out: two rows showing formatted values, tap → `showCupertinoModalPopup` with `CupertinoDatePicker(mode: CupertinoDatePickerMode.dateAndTime, ...)`, buffering into a local `picked` and committing on Done (exact pattern: `event_edit_screen.dart:566-596`). Default check-in 15:00, check-out 11:00 next day when blank. Client-side guard: check-out must be after check-in (inline error text, disable Save).
  - Rooms: draft rows with label + confirmation + notes `CupertinoTextField`s and a minus button; "Add room" `CupertinoButton`. At 320pt the three fields stack vertically inside each room card.
  - Booking/event pickers: two rows opening `showCupertinoModalPopup` with a `CupertinoPicker` over options fetched from existing providers (bookings list provider from `features/bookings`, events from the dashboard/events list provider — grep for an existing lightweight list; if none is convenient, fetch via the bookings repository directly in `initState` and keep a "None" first entry). Remember the `UncontrolledProviderScope` re-attach for popups.
  - Notes: multi-line `CupertinoTextField(maxLines: 5)`.
- [ ] **Step 3: Save.**
```dart
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(lodgingRepositoryProvider);
      final bandId = ref.read(selectedBandProvider).value!;
      final rooms = _rooms
          .where((r) => r.label.text.trim().isNotEmpty)
          .map((r) => LodgingRoom(
                id: r.id,
                label: r.label.text.trim(),
                confirmationNumber: r.confirmation.text.trim().isEmpty
                    ? null
                    : r.confirmation.text.trim(),
                notes: r.notes.text.trim().isEmpty ? null : r.notes.text.trim(),
              ))
          .toList();

      if (widget.lodgingId == null) {
        final created = await repo.createLodging(
          bandId,
          name: _nameController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          latitude: _lat,
          longitude: _lng,
          checkInAt: _wire(_checkIn!),
          checkOutAt: _wire(_checkOut!),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          bookingId: _bookingId,
          eventId: _eventId,
          rooms: rooms,
        );
        _invalidate(bandId, created.id);
        if (mounted) context.pushReplacement('/lodging/${created.id}');
      } else {
        await repo.updateLodging(bandId, widget.lodgingId!, {
          'name': _nameController.text.trim(),
          'address': _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          'latitude': _lat,
          'longitude': _lng,
          'check_in_at': _wire(_checkIn!),
          'check_out_at': _wire(_checkOut!),
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          'booking_id': _bookingId,
          'event_id': _eventId,
          'rooms': rooms.map((r) => r.toJson()).toList(),
        });
        _invalidate(bandId, widget.lodgingId!);
        if (mounted) context.pop();
      }
    } catch (e) {
      // CupertinoAlertDialog error pattern from rehearsal_detail_screen.dart:199-218
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _wire(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:00';

  void _invalidate(int bandId, int lodgingId) {
    // Guarded fan-out (rehearsal_detail_screen.dart:221-232)
    try {
      ref.invalidate(lodgingsProvider(bandId));
      ref.invalidate(lodgingDetailProvider(lodgingId));
    } catch (_) {}
  }
```
- [ ] **Step 4: Delete** (edit mode only): red "Delete Lodging" `CupertinoButton` → `showCupertinoDialog` confirm → `repo.deleteLodging(...)` → `ref.read(lodgingsProvider(bandId).notifier).remove(id)` → pop to list.
- [ ] **Step 5: Run + analyze + commit**

Run: `flutter test && flutter analyze`
Expected: PASS, clean

```bash
git add lib test
git commit -m "feat(lodging): create/edit screen with rooms, address, datetime pickers"
```

---

### Task 6: Event/booking detail lodging cards + legacy mobile lodging removal

**Files:**
- Modify: `lib/features/events/data/models/event_detail.dart` (remove `LodgingItem` class `:180-191` + `lodging` field `:222,274,295-298,358`; add `lodgings` summary list)
- Modify: `lib/features/events/screens/event_detail_screen.dart` (`:241-246` — replace `_LodgingSection` gate + section; delete `_LodgingSection` widget)
- Modify: `lib/features/events/data/events_repository.dart:98` (remove legacy lodging write)
- Modify: booking detail screen (`lib/features/bookings/screens/booking_detail_screen.dart`) + its model — add `lodgings` summary parse + card
- Test: update `test/features/events/` model tests that reference `lodging`; add parse coverage for `lodgings`

**Interfaces:**
- Consumes: backend `lodgings` summary key on event + booking detail payloads (backend Task 4): `[{id, name, address, check_in_at, check_out_at, room_count, attachment_count, booking_id, event_id}]`.
- Produces: `EventDetail.lodgings` (`List<LodgingSummary>` imported from the lodging feature), lodging card on both detail screens navigating to `/lodging/:id`.

- [ ] **Step 1: Model swap.** In `event_detail.dart`: delete the `LodgingItem` class; replace the `lodging` field with `final List<LodgingSummary> lodgings;` (import `../../lodging/data/models/lodging.dart` — cross-feature model import is acceptable here; the summary is the lodging feature's public wire type). Parse:
```dart
    final rawLodgings = json['lodgings'];
    final lodgings = rawLodgings is List
        ? rawLodgings.cast<Map<String, dynamic>>().map(LodgingSummary.fromJson).toList()
        : <LodgingSummary>[];
```
Fix every constructor call site the analyzer flags (screens, tests).
- [ ] **Step 2: Event detail card.** Replace the legacy gate at `event_detail_screen.dart:241-246` with:
```dart
            if (event.lodgings.isNotEmpty) ...[
              const _SectionHeader(title: 'Lodging'),
              _LodgingLinksSection(lodgings: event.lodgings),
            ],
```
`_LodgingLinksSection` renders one tappable row per stay (name, `DateFormat('EEE, MMM d')` range, chevron) → `context.push('/lodging/${l.id}')`. Delete the old `_LodgingSection` widget and any now-unused imports.
- [ ] **Step 3: Repository cleanup.** Remove the legacy `lodging` key from the update payload in `events_repository.dart` (line ~98) and any event-edit UI that fed it (grep `lodging` across `lib/features/events/` and `lib/features/bookings/` — remove dead paths the analyzer confirms unused; do NOT touch the backend contract otherwise).
- [ ] **Step 4: Booking detail.** In the booking detail model (grep `class BookingDetail` in `lib/features/bookings/data/models/`), add the same `lodgings` parse; render the same `_LodgingLinksSection`-style card in `booking_detail_screen.dart` near venue/schedule info.
- [ ] **Step 5: Tests.** Fix compile-broken tests; add to the events model test file:
```dart
    test('parses lodgings summary list', () {
      final detail = EventDetail.fromJson({
        // ...existing minimal fixture fields...
        'lodgings': [
          {
            'id': 4, 'name': 'Gig Hotel',
            'check_in_at': '2030-05-01 15:00:00',
            'check_out_at': '2030-05-02 11:00:00',
            'room_count': 2, 'attachment_count': 0,
          }
        ],
      });
      expect(detail.lodgings.single.name, 'Gig Hotel');
    });
```
(Copy the existing minimal `EventDetail` fixture from the current test file for the other required keys.)
- [ ] **Step 6: Run full suite + analyze + commit**

Run: `flutter test && flutter analyze`
Expected: PASS, clean

```bash
git add lib test
git commit -m "feat(lodging): lodging cards on event/booking detail, remove legacy lodging UI"
```

---

### Task 7: On-device verification + PR

- [ ] **Step 1:** Verify local backend has the lodging branch migrated (`docker-compose exec app php artisan migrate` in the TTS repo) — or the backend PR is already on staging.
- [ ] **Step 2:** Use the `run-on-device` skill to launch on the Android phone against the local backend. **Re-login first** (new token abilities). Drive: Operations → Lodging → create a stay with 2 rooms + address + photo → verify maps tap opens Google Maps → link it to a booking → confirm the card shows on that booking's detail screen and the event card when event-linked. Screenshot the list, detail, and edit screens.
- [ ] **Step 3:** Run the full suite one final time: `flutter test && flutter analyze`.
- [ ] **Step 4:** Push + PR (base `main`):
```bash
git push -u origin feat/lodging
gh pr create --base main --title "feat: lodging — standalone stays with rooms, photos, and maps navigation" --body "$(cat <<'EOF'
## Summary
- New Lodging feature: list/detail/create/edit under Operations tab
- Rooms with confirmation numbers, check-in/check-out datetimes, notes
- Image attachments (authenticated serving, lightbox), maps navigation via shared helper
- Lodging cards on event and booking detail; legacy additional_data lodging UI removed
- Realtime invalidation registry entry for the lodging model

Backend: requires TTS lodging PR deployed (new read:lodging/write:lodging abilities).

## Test plan
- [ ] flutter test + analyze green
- [ ] On-device: create/edit/delete stay, photo upload, maps tap, booking/event cards

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
- [ ] **Step 5:** Wait for the Copilot auto-review and address comments. Do not merge before the backend PR has merged (staging auto-deploy) — merge order is load-bearing.
