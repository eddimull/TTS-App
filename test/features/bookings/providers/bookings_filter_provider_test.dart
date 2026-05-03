import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_status.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_filter_provider.dart';

void main() {
  group('BookingsFilterState', () {
    test('default state is not active', () {
      const state = BookingsFilterState();
      expect(state.status, BookingStatus.all);
      expect(state.hiddenBandIds, isEmpty);
      expect(state.isActive, false);
      expect(state.activeCount, 0);
    });

    test('non-all status counts as 1 active', () {
      const state = BookingsFilterState(status: BookingStatus.confirmed);
      expect(state.isActive, true);
      expect(state.activeCount, 1);
    });

    test('hidden bands count toward activeCount', () {
      const state = BookingsFilterState(hiddenBandIds: {1, 2});
      expect(state.activeCount, 2);
    });

    test('status + hidden bands sum', () {
      const state = BookingsFilterState(
        status: BookingStatus.pending,
        hiddenBandIds: {7},
      );
      expect(state.activeCount, 2);
    });

    test('value-equality on identical state', () {
      const a = BookingsFilterState(
        status: BookingStatus.draft,
        hiddenBandIds: {1, 2},
      );
      const b = BookingsFilterState(
        status: BookingStatus.draft,
        hiddenBandIds: {1, 2},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('BookingsFilterNotifier', () {
    test('setStatus updates status', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(bookingsFilterProvider.notifier)
          .setStatus(BookingStatus.confirmed);

      expect(container.read(bookingsFilterProvider).status,
          BookingStatus.confirmed);
    });

    test('toggleBand adds and removes a band id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(bookingsFilterProvider.notifier);
      notifier.toggleBand(5);
      expect(container.read(bookingsFilterProvider).hiddenBandIds, {5});

      notifier.toggleBand(5);
      expect(container.read(bookingsFilterProvider).hiddenBandIds, isEmpty);
    });

    test('clear resets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(bookingsFilterProvider.notifier);
      notifier.setStatus(BookingStatus.pending);
      notifier.toggleBand(1);
      notifier.toggleBand(2);
      expect(container.read(bookingsFilterProvider).isActive, true);

      notifier.clear();
      final state = container.read(bookingsFilterProvider);
      expect(state.status, BookingStatus.all);
      expect(state.hiddenBandIds, isEmpty);
      expect(state.isActive, false);
    });
  });
}
