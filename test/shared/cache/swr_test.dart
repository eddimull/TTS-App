// test/shared/cache/swr_test.dart
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
  });
}
