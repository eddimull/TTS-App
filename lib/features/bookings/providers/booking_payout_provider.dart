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

  Future<void> addAdjustment({
    required double amount,
    required String description,
    String? notes,
  }) async {
    await ref.read(bookingsRepositoryProvider).addPayoutAdjustment(
      _key.bandId,
      _key.bookingId,
      {
        'amount': amount,
        'description': description,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    await _refresh();
  }

  Future<void> deleteAdjustment(int adjustmentId) async {
    await ref.read(bookingsRepositoryProvider).deletePayoutAdjustment(
          _key.bandId,
          _key.bookingId,
          adjustmentId,
        );
    await _refresh();
  }

  Future<void> switchConfig(int configId) async {
    await ref.read(bookingsRepositoryProvider).updatePayoutConfiguration(
          _key.bandId,
          _key.bookingId,
          configId,
        );
    await _refresh();
  }

  Future<void> setAttendance(int eventId, int memberId, String status) async {
    await ref.read(bookingsRepositoryProvider).updateAttendance(
          _key.bandId,
          _key.bookingId,
          eventId,
          memberId,
          status,
        );
    await _refresh();
  }
}

final bookingPayoutProvider = AsyncNotifierProvider.autoDispose
    .family<BookingPayoutNotifier, BookingPayout, BookingPayoutKey>(
  BookingPayoutNotifier.new,
);
