import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/screens/lodging_edit_screen.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

final _throwingDio = Dio();

/// `eventDetailProvider` now uses the shared SWR mixin, which reads
/// `apiCacheStorageProvider` whenever a band is selected. Without this
/// override the provider throws `UnimplementedError` on any rebuild that
/// happens after `selectedBandProvider` has resolved (e.g. the invalidate
/// triggered by save/delete below).
Future<ApiCacheStorage> _fakeCacheStorage() async {
  SharedPreferences.setMockInitialValues({});
  return ApiCacheStorage(await SharedPreferences.getInstance());
}


class _FakeBookingsRepository extends BookingsRepository {
  _FakeBookingsRepository({this.bookings = const []}) : super(_throwingDio);

  int getBookingDetailCalls = 0;
  final List<BookingSummary> bookings;

  @override
  Future<List<BookingSummary>> getBandBookings(
    int bandId, {
    String? status,
    bool upcomingOnly = false,
    int? year,
  }) async {
    return bookings;
  }

  @override
  Future<BookingDetail> getBookingDetail(int bandId, int bookingId) async {
    getBookingDetailCalls++;
    return BookingDetail(
      id: bookingId,
      name: 'Test Booking',
      startDate: '2026-09-01',
      endDate: '2026-09-01',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      contacts: const [],
      events: const [],
    );
  }
}

class _FakeEventsRepository extends EventsRepository {
  _FakeEventsRepository() : super(_throwingDio);

  int getEventDetailCalls = 0;

  Map<String, dynamic> _eventJson(String key) => {
        'event': {
          'id': 1,
          'key': key,
          'title': 'Test Event',
          'date': '2026-09-01',
          'can_write': false,
          'members': [],
          'timeline': [],
          'contacts': [],
          'attachments': [],
        },
      };

  @override
  Future<EventDetail> getEventDetail(String key) async {
    getEventDetailCalls++;
    return EventsRepository.parseEventDetail(_eventJson(key));
  }

  @override
  Future<({EventDetail parsed, Map<String, dynamic> raw})> getEventDetailRaw(
      String key) async {
    getEventDetailCalls++;
    final data = _eventJson(key);
    return (parsed: EventsRepository.parseEventDetail(data), raw: data);
  }
}

class _FakeLodgingRepository extends LodgingRepository {
  _FakeLodgingRepository() : super(_throwingDio);

  Map<String, dynamic>? lastCreateArgs;
  Map<String, dynamic>? lastUpdatePatch;
  bool deleted = false;

  /// When true, [getLodging] returns a lodging with one pre-existing room
  /// (id: 42) and a non-null `notes` field, so save-path tests can exercise
  /// "keep the existing room + add a new one" and "clear an optional field".
  bool withExistingRoomAndNotes = false;

  @override
  Future<({Lodging lodging, bool canWrite})> getLodging(
      int bandId, int lodgingId) async {
    return (
      lodging: Lodging(
        id: lodgingId,
        name: 'Existing Hotel',
        checkInAt: DateTime(2026, 9, 1, 15).toIso8601String(),
        checkOutAt: DateTime(2026, 9, 2, 11).toIso8601String(),
        notes: withExistingRoomAndNotes ? 'Original notes' : null,
        rooms: withExistingRoomAndNotes
            ? const [LodgingRoom(id: 42, label: 'Room 214')]
            : const [],
        attachments: const [],
      ),
      canWrite: true,
    );
  }

  @override
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
    lastCreateArgs = {
      'name': name,
      'checkInAt': checkInAt,
      'checkOutAt': checkOutAt,
      'rooms': rooms,
    };
    return Lodging(
      id: 99,
      name: name,
      checkInAt: checkInAt,
      checkOutAt: checkOutAt,
      rooms: rooms,
      attachments: const [],
    );
  }

  @override
  Future<Lodging> updateLodging(
      int bandId, int lodgingId, Map<String, dynamic> patch) async {
    lastUpdatePatch = patch;
    return Lodging(
      id: lodgingId,
      name: patch['name'] as String? ?? 'Existing Hotel',
      checkInAt: patch['check_in_at'] as String? ?? '',
      checkOutAt: patch['check_out_at'] as String? ?? '',
      rooms: const [],
      attachments: const [],
    );
  }

  @override
  Future<void> deleteLodging(int bandId, int lodgingId) async {
    deleted = true;
  }
}

class _FakeBand extends SelectedBandNotifier {
  _FakeBand(this._id);
  final int? _id;
  @override
  Future<int?> build() async => _id;
}

/// Keeps [bookingDetailProvider] and [eventDetailProvider] watched (as the
/// real booking/event detail screens do), so a test can observe whether
/// `ref.invalidate(...)` elsewhere actually triggers a refetch.
class _DetailWatchers extends ConsumerWidget {
  const _DetailWatchers({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bookingDetailProvider((bandId: 1, bookingId: 1)));
    ref.watch(eventDetailProvider('evt-1'));
    return child;
  }
}

void main() {
  testWidgets('create mode: entering a name enables Save and calls createLodging',
      (tester) async {
    final lodgingRepo = _FakeLodgingRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(lodgingRepo),
        bookingsRepositoryProvider.overrideWithValue(_FakeBookingsRepository()),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
        apiCacheStorageProvider.overrideWithValue(await _fakeCacheStorage()),
      ],
      child: const CupertinoApp(home: LodgingEditScreen(lodgingId: null)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Lodging'), findsOneWidget);

    // Default dates are already valid; entering a name is what's needed to
    // exercise the create-and-save path below.
    await tester.enterText(find.byType(CupertinoTextField).first, 'Marriott Downtown');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(lodgingRepo.lastCreateArgs, isNotNull);
    expect(lodgingRepo.lastCreateArgs!['name'], 'Marriott Downtown');
  });

  testWidgets('edit mode: prefills existing lodging and deletes on confirm',
      (tester) async {
    final lodgingRepo = _FakeLodgingRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(lodgingRepo),
        bookingsRepositoryProvider.overrideWithValue(_FakeBookingsRepository()),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
        apiCacheStorageProvider.overrideWithValue(await _fakeCacheStorage()),
      ],
      child: const CupertinoApp(home: LodgingEditScreen(lodgingId: 5)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Edit Lodging'), findsOneWidget);
    expect(find.text('Existing Hotel'), findsOneWidget);

    // The delete button sits below the fold in the ListView; scroll it into
    // view before asserting/tapping (ListView only mounts elements within
    // the viewport + cache extent).
    await tester.dragUntilVisible(
      find.text('Delete Lodging'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Delete Lodging'), findsOneWidget);

    await tester.tap(find.text('Delete Lodging'));
    await tester.pumpAndSettle();
    // Confirm dialog
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(lodgingRepo.deleted, isTrue);
  });

  testWidgets(
      'edit mode: delete invalidates bookingDetailProvider and '
      'eventDetailProvider (same full set as save), so a booking/event '
      'detail screen that already loaded this lodging refetches instead of '
      'showing a stale card', (tester) async {
    final lodgingRepo = _FakeLodgingRepository();
    final bookingsRepo = _FakeBookingsRepository();
    final eventsRepo = _FakeEventsRepository();

    // _Watchers keeps bookingDetailProvider/eventDetailProvider "warm" (an
    // active listener), exactly like the booking/event detail screens do in
    // the real app. Without an active watcher, invalidate() would have
    // nothing to refetch and this test couldn't observe anything.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(lodgingRepo),
        bookingsRepositoryProvider.overrideWithValue(bookingsRepo),
        eventsRepositoryProvider.overrideWithValue(eventsRepo),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
        apiCacheStorageProvider.overrideWithValue(await _fakeCacheStorage()),
      ],
      child: const CupertinoApp(
        home: _DetailWatchers(
          child: LodgingEditScreen(lodgingId: 5),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(bookingsRepo.getBookingDetailCalls, 1);
    expect(eventsRepo.getEventDetailCalls, 1);

    await tester.dragUntilVisible(
      find.text('Delete Lodging'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Delete Lodging'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(lodgingRepo.deleted, isTrue);
    expect(bookingsRepo.getBookingDetailCalls, 2,
        reason: 'delete must invalidate bookingDetailProvider, same as save');
    expect(eventsRepo.getEventDetailCalls, 2,
        reason: 'delete must invalidate eventDetailProvider, same as save');
  });

  testWidgets(
      'edit mode: save sends renamed name, wired dates, full rooms list '
      '(existing id kept + new room without id), and a cleared notes field',
      (tester) async {
    final lodgingRepo = _FakeLodgingRepository()
      ..withExistingRoomAndNotes = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(lodgingRepo),
        bookingsRepositoryProvider.overrideWithValue(_FakeBookingsRepository()),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
        apiCacheStorageProvider.overrideWithValue(await _fakeCacheStorage()),
      ],
      child: const CupertinoApp(home: LodgingEditScreen(lodgingId: 5)),
    ));
    await tester.pumpAndSettle();

    // Prefill sanity check: the existing room's label made it into the form.
    expect(find.text('Room 214'), findsOneWidget);

    // Rename.
    await tester.enterText(
        find.byType(CupertinoTextField).first, 'Renamed Hotel');
    await tester.pumpAndSettle();

    // Clear the prefilled top-level notes field (was "Original notes") — it
    // sits below the fold in the ListView, so scroll it into view first.
    final notesField =
        find.widgetWithText(CupertinoTextField, 'Original notes');
    await tester.dragUntilVisible(
      notesField,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(notesField, '');
    await tester.pumpAndSettle();

    // Add a second room (no id — a fresh insert) and give it a label so it
    // survives the "drop empty rows" filter on save.
    await tester.dragUntilVisible(
      find.text('Add room'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Add room'));
    await tester.pumpAndSettle();

    // Two fields share this placeholder (the prefilled "Room 214" row and
    // the new empty row) since CupertinoTextField's text finder matches on
    // placeholder as well as content — narrow to the one with empty content.
    final newRoomLabelField = find.byWidgetPredicate((w) =>
        w is CupertinoTextField &&
        w.placeholder == 'Room label (e.g. Room 214)' &&
        (w.controller?.text.isEmpty ?? true));
    expect(newRoomLabelField, findsOneWidget);
    await tester.enterText(newRoomLabelField, 'Room 305');
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Save'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final patch = lodgingRepo.lastUpdatePatch;
    expect(patch, isNotNull);
    expect(patch!['name'], 'Renamed Hotel');
    expect(patch['check_in_at'], '2026-09-01 15:00:00');
    expect(patch['check_out_at'], '2026-09-02 11:00:00');
    expect(patch['notes'], isNull); // cleared field sent as explicit null
    expect(patch['booking_id'], isNull); // no booking picked -> None -> null
    expect(patch['event_id'], isNull); // no event picked -> None -> null

    final rooms = (patch['rooms'] as List).cast<Map<String, dynamic>>();
    expect(rooms, hasLength(2));
    expect(rooms[0]['id'], 42); // existing room keeps its id (update)
    expect(rooms[0]['label'], 'Room 214');
    expect(rooms[1].containsKey('id'), isFalse); // new room has no id (insert)
    expect(rooms[1]['label'], 'Room 305');
  });

  testWidgets('room draft: Add room then remove it drops the empty row',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(_FakeLodgingRepository()),
        bookingsRepositoryProvider.overrideWithValue(_FakeBookingsRepository()),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
        apiCacheStorageProvider.overrideWithValue(await _fakeCacheStorage()),
      ],
      child: const CupertinoApp(home: LodgingEditScreen(lodgingId: null)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Add room'), findsOneWidget);
    await tester.tap(find.text('Add room'));
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.minus_circle), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.minus_circle));
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.minus_circle), findsNothing);
  });

  testWidgets(
      'booking picker: a booking whose only event has a malformed '
      '(non-empty, unparseable) date sorts undated, not as "today"',
      (tester) async {
    // Non-empty but unparseable — the bug this regression guards against is
    // treating this as `DateTime.now()` via EventSummary.parsedDate's silent
    // fallback, which would wrongly sort it into "During your stay"/"Nearby"
    // for a fresh lodging (whose default check-in is today).
    const malformedEvent = EventSummary(
      id: 1,
      key: 'evt-1',
      title: 'Mystery Gig',
      date: 'not-a-date',
      eventSource: 'booking',
    );
    const booking = BookingSummary(
      id: 7,
      name: 'Malformed Booking',
      startDate: '',
      endDate: '',
      eventCount: 1,
      isMultiEvent: false,
      isPaid: false,
      contacts: [],
      events: [malformedEvent],
    );
    final bookingsRepo = _FakeBookingsRepository(bookings: const [booking]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(_FakeLodgingRepository()),
        bookingsRepositoryProvider.overrideWithValue(bookingsRepo),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
        apiCacheStorageProvider.overrideWithValue(await _fakeCacheStorage()),
      ],
      child: const CupertinoApp(home: LodgingEditScreen(lodgingId: null)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Booking'));
    await tester.pumpAndSettle();

    // The booking tile renders — but with no date subtitle beneath its
    // label, proving `_bookingDate` returned null (undated) rather than
    // `DateTime.now()`. A non-null date would render an
    // "EEE, MMM d, yyyy"-formatted line under the label.
    final tile = find.ancestor(
      of: find.text('Malformed Booking'),
      matching: find.byType(Column),
    );
    expect(tile, findsWidgets);
    final dateTexts = tester
        .widgetList<Text>(find.descendant(
          of: tile.first,
          matching: find.byType(Text),
        ))
        .where((t) => t.data != 'Malformed Booking');
    expect(dateTexts, isEmpty,
        reason: 'undated booking must not render a date subtitle');
  });
}
