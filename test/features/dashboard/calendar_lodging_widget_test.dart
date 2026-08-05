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
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

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
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async =>
          (events: const <EventSummary>[], upcomingCharts: const <UpcomingChart>[]);

  @override
  Future<List<EventSummary>> loadOlderEvents(String beforeDate) async => const [];

  @override
  Future<List<EventSummary>> loadNewerEvents(
      String afterDate, String beforeDate) async => const [];
}

/// One stay covering now()+3d..now()+5d (check-in day, a middle day, and a
/// check-out day).
class _FakeLodgingRepository extends LodgingRepository {
  _FakeLodgingRepository() : super(_throwingDio);

  final checkIn = DateTime.now().add(const Duration(days: 3, hours: 15));
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

  Widget host(_FakeLodgingRepository lodgingRepo) {
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
      ],
      child: const CupertinoApp(home: Material(child: DashboardScreen())),
    );
  }

  Future<void> pumpDashboard(
      WidgetTester tester, _FakeLodgingRepository repo) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(repo));
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
