import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
