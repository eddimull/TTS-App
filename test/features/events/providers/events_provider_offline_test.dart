import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/events/providers/events_provider.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

Map<String, dynamic> _eventJson(int id, String title) => {
      'id': id,
      'key': 'evt-$id',
      'title': title,
      'date': '2026-09-01',
    };

class _StubEventsRepo implements EventsRepository {
  // ignore: unused_element_parameter
  _StubEventsRepo({this.listResponse, this.detailResponse, this.error});

  Map<String, dynamic>? listResponse;
  Map<String, dynamic>? detailResponse;
  Object? error;
  int listCalls = 0;
  int detailCalls = 0;

  @override
  Future<({List<EventSummary> parsed, Map<String, dynamic> raw})>
      getBandEventsRaw(int bandId, {String? from, String? to}) async {
    listCalls++;
    if (error != null) throw error!;
    final data = listResponse!;
    return (parsed: EventsRepository.parseBandEvents(data), raw: data);
  }

  @override
  Future<({EventDetail parsed, Map<String, dynamic> raw})> getEventDetailRaw(
      String key) async {
    detailCalls++;
    if (error != null) throw error!;
    final data = detailResponse!;
    return (parsed: EventsRepository.parseEventDetail(data), raw: data);
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
  late _StubEventsRepo repo;

  Future<ProviderContainer> makeContainer({bool online = true}) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(AsyncValue.data(online)),
      eventsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);
    await _flushMicrotasks();
    return container;
  }

  const params = BandEventsParams(bandId: 7);

  test('events list: cold fetch populates the cache', () async {
    repo = _StubEventsRepo(listResponse: {
      'events': [_eventJson(1, 'Gig A')],
    });
    final container = await makeContainer();
    final events = await container.read(bandEventsProvider(params).future);
    expect(events.single.title, 'Gig A');
    expect(storage.read('7:events:7::'), isNotNull);
  });

  test('events list: warm paint from cache, then revalidates', () async {
    repo = _StubEventsRepo(listResponse: {
      'events': [_eventJson(2, 'Fresh gig')],
    });
    final container = await makeContainer();
    storage.write('7:events:7::', {
      'events': [_eventJson(1, 'Cached gig')],
    });

    final first = await container.read(bandEventsProvider(params).future);
    expect(first.single.title, 'Cached gig');
    await _flushMicrotasks();
    expect(
        container.read(bandEventsProvider(params)).value!.single.title,
        'Fresh gig');
  });

  test('events list: refresh keeps data on connection error, no loading',
      () async {
    repo = _StubEventsRepo(listResponse: {
      'events': [_eventJson(1, 'Gig A')],
    });
    final container = await makeContainer();
    await container.read(bandEventsProvider(params).future);

    final states = <AsyncValue<List<EventSummary>>>[];
    container.listen(bandEventsProvider(params), (_, next) => states.add(next));

    repo.error = _connectionError();
    await container.read(bandEventsProvider(params).notifier).refresh();

    expect(states.whereType<AsyncLoading<List<EventSummary>>>(), isEmpty);
    expect(container.read(bandEventsProvider(params)).value!.single.title,
        'Gig A');
  });

  test('event detail: warm paint from cache when offline', () async {
    repo = _StubEventsRepo(error: _connectionError());
    final container = await makeContainer(online: false);
    storage.write('7:event:evt-1', {
      'event': _eventJson(1, 'Cached gig'),
    });

    final detail = await container.read(eventDetailProvider('evt-1').future);
    expect(detail.title, 'Cached gig');
    // Let the deferred background revalidate (scheduled by swrBuild's warm
    // path) finish before addTearDown disposes the container.
    await _flushMicrotasks();
  });

  test('event detail: offline with empty cache throws OfflineException',
      () async {
    repo = _StubEventsRepo(error: _connectionError());
    final container = await makeContainer(online: false);

    bool gotError = false;
    container.listen(eventDetailProvider('evt-9'), (_, state) {
      if (state.hasError) {
        expect(state.error, isA<OfflineException>());
        gotError = true;
      }
    });

    // Trigger the build.
    container.read(eventDetailProvider('evt-9'));

    await _flushMicrotasks();
    expect(gotError, isTrue);
  });
}
