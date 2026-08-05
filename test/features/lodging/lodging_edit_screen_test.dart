import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/screens/lodging_edit_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

final _throwingDio = Dio();

class _FakeBookingsRepository extends BookingsRepository {
  _FakeBookingsRepository() : super(_throwingDio);

  @override
  Future<List<BookingSummary>> getBandBookings(
    int bandId, {
    String? status,
    bool upcomingOnly = false,
    int? year,
  }) async {
    return const [];
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

void main() {
  testWidgets('create mode: entering a name enables Save and calls createLodging',
      (tester) async {
    final lodgingRepo = _FakeLodgingRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        lodgingRepositoryProvider.overrideWithValue(lodgingRepo),
        bookingsRepositoryProvider.overrideWithValue(_FakeBookingsRepository()),
        selectedBandProvider.overrideWith(() => _FakeBand(1)),
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
}
