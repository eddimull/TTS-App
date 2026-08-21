// test/shared/cache/swr_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

/// Selected-band stub: band 7, resolved synchronously.
class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

/// A [SelectedBandNotifier] whose value can be changed mid-test via
/// [switchTo] — used to simulate a band switch landing while a revalidate
/// fetch is in flight.
class _SwitchableBandNotifier extends SelectedBandNotifier {
  _SwitchableBandNotifier(this._initial);
  final int _initial;

  @override
  Future<int?> build() async => _initial;

  void switchTo(int? bandId) => state = AsyncValue.data(bandId);
}

typedef _Fetch = Future<({List<String> value, Map<String, dynamic> raw})>
    Function();

/// Minimal concrete notifier exercising the mixin.
class _TestNotifier extends AsyncNotifier<List<String>>
    with SwrSupport<List<String>> {
  _TestNotifier(this.fetcher);
  final _Fetch fetcher;

  static List<String> decode(Map<String, dynamic> payload) =>
      (payload['items'] as List<dynamic>).cast<String>();

  @override
  Future<List<String>> build() =>
      swrBuild(name: 'test', decode: decode, fetch: fetcher);

  Future<void> refresh() => swrRevalidate(name: 'test', fetch: fetcher);
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

  Future<ProviderContainer> makeContainer({
    required _Fetch fetch,
    bool online = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(AsyncValue.data(online)),
    ]);
    // Wait for the band provider to resolve.
    await container.read(selectedBandProvider.future);
    // Flush any pending microtasks.
    await _flushMicrotasks();
    return container;
  }

  late _Fetch fetcher;
  final provider = AsyncNotifierProvider<_TestNotifier, List<String>>(
    () => _TestNotifier(() => fetcher()),
  );

  group('isOfflineError', () {
    test('true for connection-type DioExceptions and OfflineException', () {
      expect(isOfflineError(_connectionError()), isTrue);
      expect(isOfflineError(const OfflineException()), isTrue);
      expect(
        isOfflineError(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionTimeout,
        )),
        isTrue,
      );
    });

    test('false for HTTP-response errors and plain exceptions', () {
      expect(
        isOfflineError(DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: RequestOptions(path: '/x'), statusCode: 500),
        )),
        isFalse,
      );
      expect(isOfflineError(Exception('nope')), isFalse);
    });
  });

  group('swrBuild', () {
    test('cold path fetches, caches, and returns fresh data', () async {
      fetcher = () async => (value: ['fresh'], raw: {'items': ['fresh']});
      final container = await makeContainer(fetch: () => fetcher());
      final result = await container.read(provider.future);
      expect(result, ['fresh']);
      expect(storage.read('7:test')!.payload['items'], ['fresh']);
      addTearDown(container.dispose);
    });

    test('warm path paints cache instantly then revalidates', () async {
      var calls = 0;
      fetcher = () async {
        calls++;
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final container = await makeContainer(fetch: () => fetcher());
      storage.write('7:test', {'items': ['cached']});

      final first = await container.read(provider.future);
      expect(first, ['cached']); // instant paint, no network await

      await _flushMicrotasks();
      expect(calls, 1);
      expect(container.read(provider).value, ['fresh']);
      expect(storage.read('7:test')!.payload['items'], ['fresh']);
      addTearDown(container.dispose);
    });

    test('warm path keeps cached data when revalidate hits a connection error',
        () async {
      fetcher = () async => throw _connectionError();
      final container = await makeContainer(fetch: () => fetcher());
      storage.write('7:test', {'items': ['cached']});

      final first = await container.read(provider.future);
      expect(first, ['cached']);
      await _flushMicrotasks();
      final state = container.read(provider);
      expect(state.hasError, isFalse);
      expect(state.value, ['cached']);
      addTearDown(container.dispose);
    });

    test('cold path offline with empty cache throws OfflineException',
        () async {
      fetcher = () async => (value: ['fresh'], raw: {'items': ['fresh']});
      final container =
          await makeContainer(fetch: () => fetcher(), online: false);

      bool gotError = false;
      container.listen(provider, (_, state) {
        if (state.hasError) {
          expect(state.error, isA<OfflineException>());
          gotError = true;
        }
      });

      // Trigger the build
      container.read(provider);

      await _flushMicrotasks();
      expect(gotError, isTrue);
      addTearDown(container.dispose);
    });
  });

  group('swrRevalidate', () {
    test('never emits loading and keeps data on failure', () async {
      var shouldThrow = false;
      fetcher = () async {
        if (shouldThrow) throw _connectionError();
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final container = await makeContainer(fetch: () => fetcher());
      await container.read(provider.future);

      final states = <AsyncValue<List<String>>>[];
      container.listen(provider, (_, next) => states.add(next));

      shouldThrow = true;
      await container.read(provider.notifier).refresh();

      expect(states.whereType<AsyncLoading<List<String>>>(), isEmpty);
      expect(container.read(provider).value, ['fresh']);
      addTearDown(container.dispose);
    });

    test('surfaces error when there is no data on screen', () async {
      fetcher = () async => throw _connectionError();
      final container =
          await makeContainer(fetch: () => fetcher(), online: false);

      bool gotError = false;
      container.listen(provider, (_, state) {
        if (state.hasError) {
          expect(state.error, isA<OfflineException>());
          gotError = true;
        }
      });

      // Trigger the build
      container.read(provider);

      await _flushMicrotasks();
      expect(gotError, isTrue);

      // Still offline, still no data: refresh keeps the error state.
      await container.read(provider.notifier).refresh();
      expect(container.read(provider).hasError, isTrue);
      addTearDown(container.dispose);
    });

    test(
        'F1: mid-flight band switch during revalidate writes nothing under '
        'either band\'s key and does not clobber the new band\'s state',
        () async {
      SharedPreferences.setMockInitialValues({});
      storage = ApiCacheStorage(await SharedPreferences.getInstance());

      final gate = Completer<void>();
      var calls = 0;
      Future<({List<String> value, Map<String, dynamic> raw})>
          gatedFetch() async {
        calls++;
        await gate.future;
        return (value: ['band A payload'], raw: {'items': ['band A payload']});
      }

      final gatedContainer = ProviderContainer(overrides: [
        apiCacheStorageProvider.overrideWithValue(storage),
        selectedBandProvider.overrideWith(() => _SwitchableBandNotifier(7)),
        connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
      ]);
      addTearDown(gatedContainer.dispose);
      final gatedProvider = AsyncNotifierProvider<_TestNotifier, List<String>>(
        () => _TestNotifier(gatedFetch),
      );

      await gatedContainer.read(selectedBandProvider.future);
      await _flushMicrotasks();

      // Seed band 7's cache so build() takes the warm path (data on screen
      // immediately) rather than awaiting the gated fetch itself — isolating
      // the in-flight switch to the swrRevalidate call under test, matching
      // how a real screen's build() already has on-screen data before its
      // background revalidate races a band switch.
      storage.write('7:test', {'items': ['band A cached']});
      // Seed band 8's cache with distinct data to prove it survives untouched.
      storage.write('8:test', {'items': ['band B cached']});

      final first = await gatedContainer.read(gatedProvider.future);
      expect(first, ['band A cached']);
      // The warm-path build() schedules a deferred revalidate via
      // `Future<void>(...)` — let it start and block on the gate.
      await _flushMicrotasks();
      expect(calls, 1);

      // Switch bands WHILE that revalidate fetch is in flight.
      final bandNotifier = gatedContainer.read(selectedBandProvider.notifier)
          as _SwitchableBandNotifier;
      bandNotifier.switchTo(8);
      await _flushMicrotasks();

      gate.complete();
      await _flushMicrotasks();
      await _flushMicrotasks();

      // Band A's in-flight payload must not have been written under band 7's
      // key (still just the original cached entry) nor under band 8's key,
      // and band 8's pre-existing cache must be completely untouched.
      expect(storage.read('7:test')!.payload['items'], ['band A cached'],
          reason: 'the in-flight fetch must not overwrite band 7\'s entry '
              'after the switch away from it');
      expect(storage.read('8:test')!.payload['items'], ['band B cached'],
          reason: "band B's cache must survive untouched — band A's "
              'in-flight revalidate payload must never be written under it');
      // And band 8's on-screen state (this same notifier instance, since
      // selectedBandProvider is not family-scoped) must not have been
      // clobbered with band A's payload either.
      expect(gatedContainer.read(gatedProvider).value, ['band A cached'],
          reason: 'aborted revalidate must leave state exactly as it was');
    });

    test(
        'F5: retry from an error state sets loading state before fetching, '
        'then resolves to fresh data', () async {
      // An ONLINE container whose first fetch fails (e.g. a transient 500,
      // not connectivity) lands in AsyncError with no data on screen. A user
      // retry (refresh) from that error state must show a loading spinner —
      // matching the hand-rolled dashboard's refresh() — rather than jumping
      // straight from error to data/error with no feedback in between.
      //
      // `container.listen` only notifies for AsyncData/AsyncError transitions
      // (Riverpod does not deliver a bare AsyncLoading notification to
      // listeners — see the "never emits loading" tests above, which rely on
      // exactly this), so the loading step is observed by gating the fetch
      // and reading `container.read(provider)` synchronously while it's
      // still in flight, rather than via a listener transcript.
      var shouldThrow = true;
      final gate = Completer<void>();
      fetcher = () async {
        await gate.future;
        if (shouldThrow) throw Exception('server error');
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final container = await makeContainer(fetch: () => fetcher());

      gate.complete();
      container.read(provider); // trigger build -> AsyncError
      await _flushMicrotasks();
      expect(container.read(provider).hasError, isTrue);

      shouldThrow = false; // the retry's fetch now succeeds
      final gate2 = Completer<void>();
      fetcher = () async {
        await gate2.future;
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final refreshFuture = container.read(provider.notifier).refresh();
      await _flushMicrotasks();

      // The fetch is now blocked on gate2 — state must already be loading.
      expect(container.read(provider), isA<AsyncLoading<List<String>>>(),
          reason: 'a retry from an error state must set loading before '
              'the fetch resolves');

      gate2.complete();
      await refreshFuture;

      expect(container.read(provider).value, ['fresh']);
      addTearDown(container.dispose);
    });

    test('F6: corrupt cached payload is dropped and falls back to a cold fetch',
        () async {
      var calls = 0;
      fetcher = () async {
        calls++;
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final container = await makeContainer(fetch: () => fetcher());
      // Write a payload whose shape decode() cannot handle: 'items' is
      // missing entirely, so `payload['items'] as List<dynamic>` throws.
      storage.write('7:test', {'not_items': 'oops'});

      final result = await container.read(provider.future);

      // Falls through to the cold-path fetch rather than permanently
      // erroring, and the bad entry is removed.
      expect(result, ['fresh']);
      expect(calls, 1);
      expect(storage.read('7:test')!.payload['items'], ['fresh']);
      addTearDown(container.dispose);
    });

    test(
        'F6: corrupt cached payload does not schedule a revalidate for the '
        'failed entry', () async {
      var calls = 0;
      fetcher = () async {
        calls++;
        return (value: ['fresh'], raw: {'items': ['fresh']});
      };
      final container = await makeContainer(fetch: () => fetcher());
      storage.write('7:test', {'not_items': 'oops'});

      await container.read(provider.future);
      // The cold-path fetch above already accounts for exactly one call.
      // Flushing microtasks must not trigger a SECOND call from a
      // mistakenly-scheduled deferred revalidate of the discarded entry.
      await _flushMicrotasks();
      expect(calls, 1);
      addTearDown(container.dispose);
    });
  });
}
