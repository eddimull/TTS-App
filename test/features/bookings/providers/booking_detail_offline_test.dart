import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/swr.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

Map<String, dynamic> _bookingJson(String name) => {
      'booking': {
        'id': 42,
        'name': name,
        'date': '2026-09-01',
        'contacts': <Map<String, dynamic>>[],
        'events': <Map<String, dynamic>>[],
      },
    };

class _StubBookingsRepo implements BookingsRepository {
  _StubBookingsRepo({this.response, this.error});

  Map<String, dynamic>? response;
  Object? error;

  @override
  Future<({BookingDetail parsed, Map<String, dynamic> raw})>
      getBookingDetailRaw(int bandId, int bookingId) async {
    if (error != null) throw error!;
    final data = response!;
    return (parsed: BookingsRepository.parseBookingDetail(data), raw: data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiCacheStorage storage;
  late _StubBookingsRepo repo;

  Future<ProviderContainer> makeContainer({bool online = true}) async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(AsyncValue.data(online)),
      bookingsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);
    await _flushMicrotasks();
    return container;
  }

  const args = (bandId: 7, bookingId: 42);

  test('cold fetch populates the cache', () async {
    repo = _StubBookingsRepo(response: _bookingJson('Wedding'));
    final container = await makeContainer();
    final detail = await container.read(bookingDetailProvider(args).future);
    expect(detail.name, 'Wedding');
    expect(storage.read('7:booking:42'), isNotNull);
  });

  test('warm paint from cache when offline', () async {
    repo = _StubBookingsRepo(
        error: DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    ));
    final container = await makeContainer(online: false);
    storage.write('7:booking:42', _bookingJson('Cached wedding'));

    final detail = await container.read(bookingDetailProvider(args).future);
    expect(detail.name, 'Cached wedding');
    // Let the deferred background revalidate (scheduled by swrBuild's warm
    // path) finish before addTearDown disposes the container.
    await _flushMicrotasks();
  });

  test('offline with empty cache throws OfflineException', () async {
    repo = _StubBookingsRepo();
    final container = await makeContainer(online: false);

    bool gotError = false;
    container.listen(bookingDetailProvider(args), (_, state) {
      if (state.hasError) {
        expect(state.error, isA<OfflineException>());
        gotError = true;
      }
    });

    // Trigger the build.
    container.read(bookingDetailProvider(args));

    await _flushMicrotasks();
    expect(gotError, isTrue);
  });
}
