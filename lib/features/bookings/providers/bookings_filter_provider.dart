import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/booking_status.dart';

/// In-memory filter state for the Bookings screen.
///
/// `status` is single-select (a booking can only have one status at a time).
/// `hiddenBandIds` is multi-select — bands the user has chosen to hide.
/// Resets on app restart (no persistence). Mirrors `LibraryFilterState`.
class BookingsFilterState {
  const BookingsFilterState({
    this.status = BookingStatus.all,
    this.hiddenBandIds = const {},
  });

  final BookingStatus status;
  final Set<int> hiddenBandIds;

  bool get isActive =>
      status != BookingStatus.all || hiddenBandIds.isNotEmpty;

  /// Count of active constraints — drives the badge on the floating button.
  /// `status != all` counts as 1; each hidden band counts as 1.
  int get activeCount =>
      (status == BookingStatus.all ? 0 : 1) + hiddenBandIds.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingsFilterState &&
          status == other.status &&
          const SetEquality<int>()
              .equals(hiddenBandIds, other.hiddenBandIds);

  @override
  int get hashCode =>
      Object.hash(status, const SetEquality<int>().hash(hiddenBandIds));

  BookingsFilterState copyWith({
    BookingStatus? status,
    Set<int>? hiddenBandIds,
  }) =>
      BookingsFilterState(
        status: status ?? this.status,
        hiddenBandIds: hiddenBandIds ?? this.hiddenBandIds,
      );
}

class BookingsFilterNotifier extends Notifier<BookingsFilterState> {
  @override
  BookingsFilterState build() => const BookingsFilterState();

  void setStatus(BookingStatus status) {
    state = state.copyWith(status: status);
  }

  void toggleBand(int bandId) {
    final next = Set<int>.from(state.hiddenBandIds);
    if (!next.add(bandId)) next.remove(bandId);
    state = state.copyWith(hiddenBandIds: next);
  }

  void clear() => state = const BookingsFilterState();
}

final bookingsFilterProvider =
    NotifierProvider<BookingsFilterNotifier, BookingsFilterState>(
  BookingsFilterNotifier.new,
);
