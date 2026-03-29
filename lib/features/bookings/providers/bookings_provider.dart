import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_detail.dart';
import '../data/models/booking_summary.dart';

// ── Band bookings (list) ──────────────────────────────────────────────────────

/// Arguments for [bandBookingsProvider].
class BandBookingsParams {
  const BandBookingsParams({
    required this.bandId,
    this.status,
    this.upcomingOnly = false,
  });

  final int bandId;
  final String? status;
  final bool upcomingOnly;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandBookingsParams &&
          runtimeType == other.runtimeType &&
          bandId == other.bandId &&
          status == other.status &&
          upcomingOnly == other.upcomingOnly;

  @override
  int get hashCode => Object.hash(bandId, status, upcomingOnly);
}

class BandBookingsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<BookingSummary>, BandBookingsParams> {
  @override
  Future<List<BookingSummary>> build(BandBookingsParams arg) async {
    final repo = ref.watch(bookingsRepositoryProvider);
    return repo.getBandBookings(
      arg.bandId,
      status: arg.status,
      upcomingOnly: arg.upcomingOnly,
    );
  }

  /// Re-fetches the list from the server.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () {
        final repo = ref.read(bookingsRepositoryProvider);
        return repo.getBandBookings(
          arg.bandId,
          status: arg.status,
          upcomingOnly: arg.upcomingOnly,
        );
      },
    );
  }
}

/// Provides the list of [BookingSummary] for a given band.
///
/// Usage:
/// ```dart
/// final bookings = ref.watch(
///   bandBookingsProvider(BandBookingsParams(bandId: 42)),
/// );
/// ```
final bandBookingsProvider = AutoDisposeAsyncNotifierProviderFamily<
    BandBookingsNotifier, List<BookingSummary>, BandBookingsParams>(
  BandBookingsNotifier.new,
);

// ── Booking detail (single) ───────────────────────────────────────────────────

/// Provides the [BookingDetail] for a single booking.
///
/// Usage:
/// ```dart
/// final detail = ref.watch(
///   bookingDetailProvider((bandId: 42, bookingId: 7)),
/// );
/// ```
final bookingDetailProvider = AutoDisposeFutureProviderFamily<BookingDetail,
    ({int bandId, int bookingId})>((ref, args) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getBookingDetail(args.bandId, args.bookingId);
});
