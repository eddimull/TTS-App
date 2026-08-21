import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/providers/calendar_filter_provider.dart';
import 'package:tts_bandmate/features/dashboard/screens/dashboard_screen.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _throwingDio = Dio();

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository() : super(_throwingDio);

  @override
  Future<
      ({
        List<EventSummary> events,
        List<UpcomingChart> upcomingCharts,
        Map<String, dynamic> raw
      })> getDashboardRaw({String? to}) async => (
        events: const <EventSummary>[],
        upcomingCharts: const <UpcomingChart>[],
        raw: const <String, dynamic>{'events': [], 'upcoming_charts': []},
      );

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async => const [];

  @override
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async => const [];
}

/// One 2-night stay (check-in day, a middle day, and a check-out day)
/// anchored to the 15th of the currently displayed month — a day-of-month
/// that only ever appears once in a `TableCalendar` month grid, so a
/// `find.text('${day}')` lookup can't collide with a leading/trailing cell
/// from an adjacent month the way a `now()+Nd` offset can near month
/// boundaries. Still relative to `now()` (not a hardcoded date), so this
/// never time-bombs.
class _FakeLodgingRepository extends LodgingRepository {
  _FakeLodgingRepository() : super(_throwingDio);

  static DateTime _anchor() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 15, 15);
  }

  final checkIn = _anchor();
  late final checkOut = checkIn.add(const Duration(days: 2));

  @override
  Future<({List<LodgingSummary> lodgings, bool canWrite})> getLodgings(
      int bandId) async {
    return (
      lodgings: [
        LodgingSummary(
          id: 42,
          name: 'Riverside Inn',
          checkInAt: checkIn.toIso8601String(),
          checkOutAt: checkOut.toIso8601String(),
          roomCount: 1,
          attachmentCount: 0,
        ),
      ],
      canWrite: false,
    );
  }
}

void main() {
  const band = BandSummary(id: 1, name: 'Alpha', isOwner: true);

  Widget host(_FakeLodgingRepository lodgingRepo, ApiCacheStorage storage) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(
              const AuthAuthenticated(
                user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
                bands: [band],
              ),
            )),
        selectedBandProvider.overrideWith(() => _StubBand()),
        dashboardRepositoryProvider
            .overrideWithValue(_FakeDashboardRepository()),
        lodgingRepositoryProvider.overrideWithValue(lodgingRepo),
        apiCacheStorageProvider.overrideWithValue(storage),
        connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
      ],
      child: const CupertinoApp(home: Material(child: DashboardScreen())),
    );
  }

  Future<void> pumpDashboard(
      WidgetTester tester, _FakeLodgingRepository repo) async {
    // Pre-dismiss both dashboard hint banners (bookings-moved, help-pointer)
    // so they don't consume vertical space on this narrow 320x640 surface —
    // this test is about the lodging agenda row, not the hints.
    SharedPreferences.setMockInitialValues({
      'hint_bookings_moved_dismissed': true,
      'hint_help_pointer_dismissed': true,
    });
    final storage = ApiCacheStorage(await SharedPreferences.getInstance());
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(repo, storage));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'agenda shows Check-in and stay name for the check-in day, and hides on toggle',
      (tester) async {
    final repo = _FakeLodgingRepository();
    await pumpDashboard(tester, repo);

    final checkInDay = repo.checkIn;

    // Select the check-in day on the calendar.
    await tester.tap(find.text('${checkInDay.day}').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Check-in'), findsOneWidget);
    expect(find.textContaining('Riverside Inn'), findsOneWidget);

    // Toggle hideLodging via the provider and confirm the row disappears.
    final context = tester.element(find.byType(DashboardScreen));
    final container = ProviderScope.containerOf(context);
    container.read(calendarFilterProvider.notifier).toggleLodging();
    await tester.pumpAndSettle();

    expect(find.textContaining('Check-in'), findsNothing);
    expect(find.textContaining('Riverside Inn'), findsNothing);
  });
}
