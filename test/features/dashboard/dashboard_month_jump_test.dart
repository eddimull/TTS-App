import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons, Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/dashboard/screens/dashboard_screen.dart';
import 'package:tts_bandmate/features/dashboard/widgets/month_year_picker_sheet.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _throwingDio = Dio();
const _itemExtent = 32.0;

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

  final List<(String, String)> requestedNewerWindows = [];

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
      String afterDate, String beforeDate) async {
    requestedNewerWindows.add((afterDate, beforeDate));
    return const [];
  }
}

void main() {
  const band = BandSummary(id: 1, name: 'Alpha', isOwner: true);

  Widget host(_FakeDashboardRepository repo, ApiCacheStorage storage) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(
              const AuthAuthenticated(
                user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
                bands: [band],
              ),
            )),
        selectedBandProvider.overrideWith(() => _StubBand()),
        dashboardRepositoryProvider.overrideWithValue(repo),
        apiCacheStorageProvider.overrideWithValue(storage),
        connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
      ],
      child: const CupertinoApp(home: Material(child: DashboardScreen())),
    );
  }

  String headerTitle(DateTime month) => DateFormat.yMMMM().format(month);

  Future<void> pumpDashboard(WidgetTester tester,
      _FakeDashboardRepository repo) async {
    SharedPreferences.setMockInitialValues({});
    final storage = ApiCacheStorage(await SharedPreferences.getInstance());
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(repo, storage));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the calendar header opens the month/year picker sheet',
      (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);

    await tester.tap(find.text(headerTitle(DateTime.now())));
    await tester.pumpAndSettle();

    expect(find.byType(MonthYearPickerSheet), findsOneWidget);
  });

  testWidgets(
      'picking a distant month jumps the calendar and triggers a month load',
      (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);
    final now = DateTime.now();

    await tester.tap(find.text(headerTitle(now)));
    await tester.pumpAndSettle();

    // Advance the wheel 1 year (via the year column, not the month column)
    // — safely beyond the ~90-day initial forward window regardless of
    // today's day-of-month, and avoids driving the linked month/year wheels
    // across a December→January rollover in a single gesture, which
    // CupertinoDatePicker's monthYear mode does not reliably cascade in
    // widget tests. Dragging the year column alone keeps the month fixed
    // and only advances the year, which is deterministic.
    final yearPicker = find.byType(CupertinoPicker).last;
    await tester.drag(yearPicker, const Offset(0, -1.5 * _itemExtent));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final target = DateTime(now.year + 1, now.month);
    expect(find.text(headerTitle(target)), findsOneWidget,
        reason: 'calendar header must now show the picked month');
    expect(repo.requestedNewerWindows, isNotEmpty,
        reason: 'jumping past the loaded window must trigger '
            'ensureMonthLoaded, same as swiping there');
  });

  testWidgets('Today resets the calendar to the current month', (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);
    final now = DateTime.now();

    // Park the calendar 4 months ahead via the header chevron first.
    final nextChevron = find.byIcon(Icons.chevron_right);
    for (var i = 0; i < 4; i++) {
      await tester.tap(nextChevron);
      await tester.pumpAndSettle();
    }
    final parked = DateTime(now.year, now.month + 4);
    expect(find.text(headerTitle(parked)), findsOneWidget);

    await tester.tap(find.text(headerTitle(parked)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(find.text(headerTitle(now)), findsOneWidget,
        reason: 'Today must park the calendar back on the current month');
    expect(find.byType(MonthYearPickerSheet), findsNothing);
  });

  testWidgets('Cancel leaves the focused month untouched', (tester) async {
    final repo = _FakeDashboardRepository();
    await pumpDashboard(tester, repo);
    final now = DateTime.now();

    await tester.tap(find.text(headerTitle(now)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text(headerTitle(now)), findsOneWidget);
    expect(find.byType(MonthYearPickerSheet), findsNothing);
  });
}
