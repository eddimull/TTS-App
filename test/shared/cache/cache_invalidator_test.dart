import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';
import 'package:tts_bandmate/features/dashboard/providers/dashboard_provider.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';

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
      const DashboardState(events: [], upcomingCharts: []);

  @override
  Future<void> refresh() async {}
}

void main() {
  test('onBookingChanged clears the bookings disk cache', () {
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
}
