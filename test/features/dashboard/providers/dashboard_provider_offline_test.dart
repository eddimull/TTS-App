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
}
