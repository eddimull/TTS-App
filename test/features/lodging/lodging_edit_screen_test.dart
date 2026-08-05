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

  @override
  Future<({Lodging lodging, bool canWrite})> getLodging(
      int bandId, int lodgingId) async {
    return (
      lodging: Lodging(
        id: lodgingId,
        name: 'Existing Hotel',
        checkInAt: DateTime(2026, 9, 1, 15).toIso8601String(),
        checkOutAt: DateTime(2026, 9, 2, 11).toIso8601String(),
        rooms: const [],
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

    // Save should be disabled until a name is entered (default dates are
    // already valid, but name is required).
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
