import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

/// A [SelectedBandNotifier] whose value can be changed mid-test via
/// [switchTo] — used to simulate a band switch that lands WHILE a
/// `refresh()` fetch is in flight.
class _SwitchableBandNotifier extends SelectedBandNotifier {
  _SwitchableBandNotifier(this._initial);
  final int _initial;

  @override
  Future<int?> build() async => _initial;

  void switchTo(int? bandId) {
    state = AsyncValue.data(bandId);
  }
}

/// A repo whose response only resolves once [gate] completes — lets a test
/// switch bands after `refresh()` has captured the pre-fetch band but before
/// the fetch itself resolves.
class _GatedDashboardRepo implements DashboardRepository {
  _GatedDashboardRepo(this.response, this.gate);

  final Map<String, dynamic> response;
  final Completer<void> gate;
  int calls = 0;

  @override
  Future<
      ({
        List<EventSummary> events,
        List<UpcomingChart> upcomingCharts,
        Map<String, dynamic> raw
      })> getDashboardRaw({String? to}) async {
    calls++;
    await gate.future;
    final parsed = DashboardRepository.parseDashboard(response);
    return (
      events: parsed.events,
      upcomingCharts: parsed.upcomingCharts,
      raw: response
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _dashboardJson(String title) => {
      'events': [
        {'id': 1, 'key': 'evt-1', 'title': title, 'date': '2026-09-01'},
      ],
      'upcoming_charts': <Map<String, dynamic>>[],
    };

class _StubDashboardRepo implements DashboardRepository {
  _StubDashboardRepo({this.response, this.error});

  Map<String, dynamic>? response;
  Object? error;
  int calls = 0;

  @override
  Future<
      ({
        List<EventSummary> events,
        List<UpcomingChart> upcomingCharts,
        Map<String, dynamic> raw
      })> getDashboardRaw({String? to}) async {
    calls++;
    if (error != null) throw error!;
    final data = response!;
    final parsed = DashboardRepository.parseDashboard(data);
    return (
      events: parsed.events,
      upcomingCharts: parsed.upcomingCharts,
      raw: data
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _connectionError() => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    );

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;
  late _StubDashboardRepo repo;

  Future<ProviderContainer> makeContainer({bool online = true}) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(AsyncValue.data(online)),
      dashboardRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);
    await _flushMicrotasks();
    return container;
  }

  test('cold fetch populates the cache', () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Live gig'));
    final container = await makeContainer();
    final state = await container.read(dashboardProvider.future);
    expect(state.events.single.title, 'Live gig');
    expect(storage.read('7:dashboard'), isNotNull);
  });

  test('warm paint from cache, then background revalidate', () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Fresh gig'));
    final container = await makeContainer();
    storage.write('7:dashboard', _dashboardJson('Cached gig'));

    final first = await container.read(dashboardProvider.future);
    expect(first.events.single.title, 'Cached gig');
    await _flushMicrotasks();
    expect(container.read(dashboardProvider).value!.events.single.title,
        'Fresh gig');
  });

  test('refresh keeps on-screen data on connection error, never loading',
      () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Live gig'));
    final container = await makeContainer();
    await container.read(dashboardProvider.future);

    final states = <AsyncValue<DashboardState>>[];
    container.listen(dashboardProvider, (_, next) => states.add(next));

    repo.error = _connectionError();
    await container.read(dashboardProvider.notifier).refresh();

    expect(states.whereType<AsyncLoading<DashboardState>>(), isEmpty);
    final after = container.read(dashboardProvider);
    expect(after.hasError, isFalse);
    expect(after.value!.events.single.title, 'Live gig');
  });

  test('offline refresh with data present skips the network entirely',
      () async {
    repo = _StubDashboardRepo(response: _dashboardJson('Cached gig'));
    final container = await makeContainer(online: false);
    storage.write('7:dashboard', _dashboardJson('Cached gig'));
    await container.read(dashboardProvider.future);
    await _flushMicrotasks();
    final callsBefore = repo.calls;

    await container.read(dashboardProvider.notifier).refresh();
    expect(repo.calls, callsBefore); // no attempt made
    expect(container.read(dashboardProvider).value!.events, isNotEmpty);
  });

  test('offline cold start with empty cache throws OfflineException',
      () async {
    repo = _StubDashboardRepo(error: _connectionError());
    final container = await makeContainer(online: false);

    bool gotError = false;
    container.listen(dashboardProvider, (_, state) {
      if (state.hasError) {
        expect(state.error, isA<OfflineException>());
        gotError = true;
      }
    });

    // Trigger the build.
    container.read(dashboardProvider);

    await _flushMicrotasks();
    expect(gotError, isTrue);
    expect(repo.calls, 0); // failed fast, no timeout wait
  });

  test(
      'refresh mid-flight band switch writes nothing under either band\'s key '
      'and does not clobber the new band\'s state', () async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final gate = Completer<void>();
    final gatedRepo =
        _GatedDashboardRepo(_dashboardJson('Band A payload'), gate);

    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(() => _SwitchableBandNotifier(7)),
      connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
      dashboardRepositoryProvider.overrideWithValue(gatedRepo),
    ]);
    addTearDown(container.dispose);

    // Seed band 7's cache too, so build() takes the warm path (instant paint
    // from disk) rather than itself awaiting the gated repo — isolating the
    // in-flight switch to the refresh() call under test, exactly like a real
    // screen's deferred background refresh racing a band switch.
    storage.write('7:dashboard', _dashboardJson('Band A cached'));
    // Seed band 8's cache with its own data so we can prove it survives
    // untouched by band A's in-flight fetch.
    storage.write('8:dashboard', _dashboardJson('Band B cached'));

    await container.read(selectedBandProvider.future);
    await _flushMicrotasks();

    final first = await container.read(dashboardProvider.future);
    expect(first.events.single.title, 'Band A cached');
    // build()'s warm path schedules a deferred refresh() via
    // `Future<void>(refresh)` — let it start and suspend on `gate.future`.
    await _flushMicrotasks();
    expect(gatedRepo.calls, 1);

    // Switch bands WHILE the fetch is in flight — mimics the user picking a
    // different band mid-refresh.
    final bandNotifier =
        container.read(selectedBandProvider.notifier) as _SwitchableBandNotifier;
    bandNotifier.switchTo(8);
    await _flushMicrotasks();

    // Now let the gated fetch resolve with band A's payload.
    gate.complete();
    await _flushMicrotasks();
    await _flushMicrotasks();

    // Band A's payload must NOT have overwritten band 7's original cache
    // entry, must NOT have been written under band 8's key, and band 8's
    // pre-existing cache must be completely untouched.
    expect(storage.read('7:dashboard')!.payload['events'][0]['title'],
        'Band A cached',
        reason: 'the in-flight fetch must not overwrite band 7\'s cache '
            'entry after the switch away from it');
    expect(storage.read('8:dashboard')!.payload['events'][0]['title'],
        'Band B cached',
        reason: "band B's cache must survive untouched — band A's in-flight "
            'payload must never be written under it');
    // Band 8's on-screen state (dashboardProvider is not band-family-scoped)
    // must not have been clobbered with band A's payload either.
    expect(container.read(dashboardProvider).value!.events.single.title,
        'Band A cached',
        reason: 'aborted refresh must leave state exactly as it was');
  });
}
