import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/payments_due.dart';
import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/shared/cache/api_cache_storage.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import 'package:tts_bandmate/shared/providers/connectivity_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

/// Records whether the bookings disk cache was cleared.
class _RecordingCache implements BookingsCacheStorage {
  int clearCount = 0;

  @override
  void clear() => clearCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Inert dashboard notifier so `dashboardProvider.notifier.refresh()` (called by
/// the invalidator) doesn't drag the real repository / band selection into this
/// unit test.
class _NoopDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardState> build() async =>
      DashboardState(
          events: const [],
          upcomingCharts: const [],
          loadedFrom: DateTime(2026),
          loadedTo: DateTime(2026, 4, 1));

  @override
  Future<void> refresh() async {}
}

/// Fake band selection so `_removeCache`'s `selectedBandProvider` read
/// resolves to band 7 synchronously, matching the `7:...` cache keys used
/// throughout this file.
class _FakeBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 7;
}

class _CountingFinancesRepo implements FinancesRepository {
  int dueFetches = 0;
  int unpaidFetches = 0;
  int paidFetches = 0;

  @override
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) async {
    unpaidFetches++;
    return const [];
  }

  @override
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) async {
    paidFetches++;
    return const [];
  }

  @override
  Future<PaymentsDue> fetchDue(int bandId) async {
    dueFetches++;
    return PaymentsDue.fromJson(const {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ApiCacheStorage storage;

  Future<ProviderContainer> makeContainer() async {
    SharedPreferences.setMockInitialValues({});
    storage = ApiCacheStorage(await SharedPreferences.getInstance());
    final cache = _RecordingCache();
    final container = ProviderContainer(overrides: [
      bookingsCacheStorageProvider.overrideWithValue(cache),
      dashboardProvider.overrideWith(_NoopDashboardNotifier.new),
      apiCacheStorageProvider.overrideWithValue(storage),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);
    return container;
  }

  test('onBookingChanged clears the bookings disk cache', () async {
    final cache = _RecordingCache();
    final container = ProviderContainer(overrides: [
      bookingsCacheStorageProvider.overrideWithValue(cache),
      dashboardProvider.overrideWith(_NoopDashboardNotifier.new),
    ]);
    addTearDown(container.dispose);

    container
        .read(cacheInvalidatorProvider)
        .onBookingChanged(bandId: 42);

    // The disk cache must be dropped so the window provider's rebuild takes the
    // cold path (fresh fetch) rather than painting stale pre-mutation data.
    expect(cache.clearCount, 1);
  });

  test('onEventChanged drops the event cache entry before invalidating',
      () async {
    final container = await makeContainer();
    storage.write('7:event:evt-1', {
      'event': {'id': 1}
    });

    container.read(cacheInvalidatorProvider).onEventChanged(eventKey: 'evt-1');

    expect(storage.read('7:event:evt-1'), isNull);
  });

  test('onEventChanged refetches payments due, since a show date sets them',
      () async {
    final repo = _CountingFinancesRepo();
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      bookingsCacheStorageProvider.overrideWithValue(_RecordingCache()),
      dashboardProvider.overrideWith(_NoopDashboardNotifier.new),
      apiCacheStorageProvider.overrideWithValue(
          ApiCacheStorage(await SharedPreferences.getInstance())),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
      financesRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);
    container.listen(paymentsDueProvider(7), (_, __) {});
    await container.read(paymentsDueProvider(7).future);
    expect(repo.dueFetches, 1);

    container.read(cacheInvalidatorProvider).onEventChanged(eventKey: 'evt-1');
    await container.read(paymentsDueProvider(7).future);

    expect(repo.dueFetches, 2);
  });

  test('onBookingDetailChanged refetches the Finances paid and unpaid lists',
      () async {
    final repo = _CountingFinancesRepo();
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      bookingsCacheStorageProvider.overrideWithValue(_RecordingCache()),
      dashboardProvider.overrideWith(_NoopDashboardNotifier.new),
      apiCacheStorageProvider.overrideWithValue(
          ApiCacheStorage(await SharedPreferences.getInstance())),
      selectedBandProvider.overrideWith(_FakeBandNotifier.new),
      connectivityProvider.overrideWithValue(const AsyncValue.data(true)),
      financesRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await container.read(selectedBandProvider.future);
    const params = FinancesParams(bandId: 7, year: 2026);
    container.listen(unpaidServicesProvider(params), (_, __) {});
    container.listen(paidServicesProvider(params), (_, __) {});
    await container.read(unpaidServicesProvider(params).future);
    await container.read(paidServicesProvider(params).future);
    expect((repo.unpaidFetches, repo.paidFetches), (1, 1));

    // A write-off (or payment) moves a booking between these lists.
    container
        .read(cacheInvalidatorProvider)
        .onBookingDetailChanged(bandId: 7, bookingId: 42);
    await container.read(unpaidServicesProvider(params).future);
    await container.read(paidServicesProvider(params).future);

    expect((repo.unpaidFetches, repo.paidFetches), (2, 2));
  });

  test('onQuestionnaireAppliedToEvents drops every event of the band only',
      () async {
    final container = await makeContainer();
    storage.write('7:event:evt-1', {'event': {'id': 1}});
    storage.write('7:event:evt-2', {'event': {'id': 2}});
    storage.write('9:event:evt-3', {'event': {'id': 3}});
    storage.write('7:booking:42', {'booking': {'id': 42}});

    container
        .read(cacheInvalidatorProvider)
        .onQuestionnaireAppliedToEvents(bandId: 7);

    expect(storage.read('7:event:evt-1'), isNull);
    expect(storage.read('7:event:evt-2'), isNull);
    expect(storage.read('9:event:evt-3'), isNotNull);
    expect(storage.read('7:booking:42'), isNotNull);
  });

  test('onBookingDetailChanged drops the booking cache entry', () async {
    final container = await makeContainer();
    storage.write('7:booking:42', {
      'booking': {'id': 42}
    });

    container.read(cacheInvalidatorProvider).onBookingDetailChanged(
        bandId: 7, bookingId: 42);

    expect(storage.read('7:booking:42'), isNull);
  });

  test('booking cache drop uses the mutation bandId, not the selected band',
      () async {
    // Selected band is 7 (makeContainer default); mutate band 9's booking.
    final container = await makeContainer();
    storage.write('9:booking:42', {
      'booking': {'id': 42},
    });
    container
        .read(cacheInvalidatorProvider)
        .onBookingDetailChanged(bandId: 9, bookingId: 42);
    expect(storage.read('9:booking:42'), isNull);
  });
}
