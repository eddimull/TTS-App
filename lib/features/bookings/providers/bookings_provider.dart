import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_detail.dart';
import '../data/models/booking_date_status.dart';
import '../data/models/booking_history_entry.dart';
import '../data/models/booking_summary.dart';
import '../data/models/contact_library_item.dart';
import '../data/models/event_type.dart';

// ── Band bookings (list) ──────────────────────────────────────────────────────

/// Arguments for [bandBookingsProvider].
class BandBookingsParams {
  const BandBookingsParams({
    required this.bandId,
    this.status,
    this.upcomingOnly = false,
    this.year,
  });

  final int bandId;
  final String? status;
  final bool upcomingOnly;

  /// When set, only bookings whose date falls in this calendar year are returned.
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BandBookingsParams &&
          runtimeType == other.runtimeType &&
          bandId == other.bandId &&
          status == other.status &&
          upcomingOnly == other.upcomingOnly &&
          year == other.year;

  @override
  int get hashCode => Object.hash(bandId, status, upcomingOnly, year);
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
      year: arg.year,
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
          year: arg.year,
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

// ── Event types ───────────────────────────────────────────────────────────────

final eventTypesProvider = FutureProvider<List<EventType>>((ref) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getEventTypes();
});

// ── Contact library (search) ──────────────────────────────────────────────────

final contactLibraryProvider = FutureProvider.autoDispose
    .family<List<ContactLibraryItem>, ({int bandId, String query})>(
        (ref, params) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getContactLibrary(params.bandId, query: params.query);
});

// ── Booking history ───────────────────────────────────────────────────────────

final bookingHistoryProvider = FutureProvider.autoDispose
    .family<List<BookingHistoryEntry>, ({int bandId, int bookingId})>(
        (ref, params) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getHistory(params.bandId, params.bookingId);
});

// ── Date status map (used by the calendar date picker) ────────────────────────

/// Returns a map from ISO date string (e.g. "2026-05-15") to the highest-priority
/// [BookingDateStatus] for that date.
///
/// Priority order: confirmed > pending > draft. If multiple bookings fall on
/// the same date, the highest-priority status wins so the calendar never
/// under-warns the user.
///
/// Only active statuses are included — cancelled bookings are excluded.
final bookingDateStatusesProvider =
    FutureProvider.autoDispose.family<Map<String, BookingDateStatus>, int>(
        (ref, bandId) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  final bookings = await repo.getBandBookings(bandId);

  final map = <String, BookingDateStatus>{};
  for (final b in bookings) {
    final status = b.status?.toLowerCase();
    // Skip cancelled / unknown statuses.
    final dateStatus = switch (status) {
      'confirmed' => BookingDateStatus.confirmed,
      'pending' => BookingDateStatus.pending,
      'draft' => BookingDateStatus.draft,
      _ => null,
    };
    if (dateStatus == null) continue;

    final existing = map[b.date];
    if (existing == null || dateStatus.priority > existing.priority) {
      map[b.date] = dateStatus;
    }
  }
  return map;
});

/// Returns a map from ISO date string (e.g. "2026-05-15") to a
/// [BookingDateInfo] that carries both the highest-priority status and the
/// title of the booking that earned that status.
///
/// When multiple bookings share a date the one with the highest-priority status
/// wins; its [BookingSummary.name] is stored as [BookingDateInfo.bookingTitle].
/// Cancelled / unknown statuses are excluded.
final bookingDateInfoProvider =
    FutureProvider.autoDispose.family<Map<String, BookingDateInfo>, int>(
        (ref, bandId) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  final bookings = await repo.getBandBookings(bandId);

  final map = <String, BookingDateInfo>{};
  for (final b in bookings) {
    final status = b.status?.toLowerCase();
    final dateStatus = switch (status) {
      'confirmed' => BookingDateStatus.confirmed,
      'pending' => BookingDateStatus.pending,
      'draft' => BookingDateStatus.draft,
      _ => null,
    };
    if (dateStatus == null) continue;

    final existing = map[b.date];
    if (existing == null || dateStatus.priority > existing.status.priority) {
      map[b.date] = BookingDateInfo(
        status: dateStatus,
        bookingTitle: b.name,
      );
    }
  }
  return map;
});
