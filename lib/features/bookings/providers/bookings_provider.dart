import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_detail.dart';
import '../data/models/booking_date_status.dart';
import '../data/models/booking_history_entry.dart';
import '../data/models/booking_summary.dart';
import '../data/models/contact_library_item.dart';
import '../data/models/event_type.dart';

// ── Band bookings (list) ──────────────────────────────────────────────────────

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

final bandBookingsProvider = FutureProvider.family<List<BookingSummary>, BandBookingsParams>(
  (ref, params) {
    final repo = ref.watch(bookingsRepositoryProvider);
    return repo.getBandBookings(
      params.bandId,
      status: params.status,
      upcomingOnly: params.upcomingOnly,
      year: params.year,
    );
  },
);

// ── Booking detail (single) ───────────────────────────────────────────────────

final bookingDetailProvider = FutureProvider.family<BookingDetail,
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

final contactLibraryProvider = FutureProvider.family<
    List<ContactLibraryItem>, ({int bandId, String query})>((ref, params) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getContactLibrary(params.bandId, query: params.query);
});

// ── Booking history ───────────────────────────────────────────────────────────

final bookingHistoryProvider = FutureProvider.family<
    List<BookingHistoryEntry>, ({int bandId, int bookingId})>((ref, params) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  return repo.getHistory(params.bandId, params.bookingId);
});

// ── Date status map ───────────────────────────────────────────────────────────

final bookingDateStatusesProvider =
    FutureProvider.family<Map<String, BookingDateStatus>, int>(
        (ref, bandId) async {
  final repo = ref.watch(bookingsRepositoryProvider);
  final bookings = await repo.getBandBookings(bandId);

  final map = <String, BookingDateStatus>{};
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
    if (existing == null || dateStatus.priority > existing.priority) {
      map[b.date] = dateStatus;
    }
  }
  return map;
});

final bookingDateInfoProvider =
    FutureProvider.family<Map<String, BookingDateInfo>, int>(
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
