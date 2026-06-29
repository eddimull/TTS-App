import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/cache/cache_invalidator.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_payout.dart';

typedef BookingPayoutKey = ({int bandId, int bookingId});

class BookingPayoutNotifier extends AsyncNotifier<BookingPayout> {
  BookingPayoutNotifier(this._key);

  final BookingPayoutKey _key;

  @override
  Future<BookingPayout> build() {
    return ref.read(bookingsRepositoryProvider).fetchPayout(_key.bandId, _key.bookingId);
  }

  Future<void> _refresh() async {
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<BookingPayout>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(bookingsRepositoryProvider).fetchPayout(_key.bandId, _key.bookingId),
    );
    ref.read(cacheInvalidatorProvider).onBookingDetailChanged(
          bandId: _key.bandId,
          bookingId: _key.bookingId,
        );
  }

  // Wraps each mutation in the same error-surfacing pattern:
  // 1. Set optimistic loading-with-previous so the UI stays populated.
  // 2. Attempt the repo call.
  // 3. On failure, surface AsyncError WITH the previous value retained
  //    (copyWithPrevious) so the screen can show an error indicator without
  //    blanking the existing data.  Then rethrow so call sites that want a
  //    local error dialog (e.g. _AddAdjustmentSheet) can still catch it.
  // 4. On success, trigger a refresh from the server.
  //
  // copyWithPrevious is marked @internal in Riverpod 3.x but is the
  // recommended way to keep state.value populated on the error path.

  Future<void> addAdjustment({
    required double amount,
    required String description,
    String? notes,
  }) async {
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<BookingPayout>().copyWithPrevious(state);
    try {
      await ref.read(bookingsRepositoryProvider).addPayoutAdjustment(
        _key.bandId,
        _key.bookingId,
        {
          'amount': amount,
          'description': description,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
    } catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<BookingPayout>.error(e, st).copyWithPrevious(state);
      rethrow;
    }
    await _refresh();
  }

  Future<void> deleteAdjustment(int adjustmentId) async {
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<BookingPayout>().copyWithPrevious(state);
    try {
      await ref.read(bookingsRepositoryProvider).deletePayoutAdjustment(
            _key.bandId,
            _key.bookingId,
            adjustmentId,
          );
    } catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<BookingPayout>.error(e, st).copyWithPrevious(state);
      rethrow;
    }
    await _refresh();
  }

  Future<void> switchConfig(int configId) async {
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<BookingPayout>().copyWithPrevious(state);
    try {
      await ref.read(bookingsRepositoryProvider).updatePayoutConfiguration(
            _key.bandId,
            _key.bookingId,
            configId,
          );
    } catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<BookingPayout>.error(e, st).copyWithPrevious(state);
      rethrow;
    }
    await _refresh();
  }

  Future<void> setAttendance(int eventId, int memberId, String status) async {
    // ignore: invalid_use_of_internal_member
    state = const AsyncLoading<BookingPayout>().copyWithPrevious(state);
    try {
      await ref.read(bookingsRepositoryProvider).updateAttendance(
            _key.bandId,
            _key.bookingId,
            eventId,
            memberId,
            status,
          );
    } catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<BookingPayout>.error(e, st).copyWithPrevious(state);
      rethrow;
    }
    await _refresh();
  }
}

final bookingPayoutProvider = AsyncNotifierProvider.autoDispose
    .family<BookingPayoutNotifier, BookingPayout, BookingPayoutKey>(
  BookingPayoutNotifier.new,
);
