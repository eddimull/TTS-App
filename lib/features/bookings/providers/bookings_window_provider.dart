import 'package:collection/collection.dart';

import '../data/models/booking_summary.dart';

/// Loaded slice of the user's bookings — what's currently in memory plus
/// the per-direction edge/loading flags that drive auto-load on scroll.
///
/// `bookings` is sorted ascending by date. `from` and `to` are inclusive.
class BookingsWindow {
  const BookingsWindow({
    required this.from,
    required this.to,
    required this.bookings,
    required this.reachedEarliest,
    required this.reachedLatest,
    required this.isLoadingEarlier,
    required this.isLoadingLater,
  });

  final DateTime from;
  final DateTime to;
  final List<BookingSummary> bookings;
  final bool reachedEarliest;
  final bool reachedLatest;
  final bool isLoadingEarlier;
  final bool isLoadingLater;

  BookingsWindow copyWith({
    DateTime? from,
    DateTime? to,
    List<BookingSummary>? bookings,
    bool? reachedEarliest,
    bool? reachedLatest,
    bool? isLoadingEarlier,
    bool? isLoadingLater,
  }) {
    return BookingsWindow(
      from: from ?? this.from,
      to: to ?? this.to,
      bookings: bookings ?? this.bookings,
      reachedEarliest: reachedEarliest ?? this.reachedEarliest,
      reachedLatest: reachedLatest ?? this.reachedLatest,
      isLoadingEarlier: isLoadingEarlier ?? this.isLoadingEarlier,
      isLoadingLater: isLoadingLater ?? this.isLoadingLater,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingsWindow &&
          from == other.from &&
          to == other.to &&
          reachedEarliest == other.reachedEarliest &&
          reachedLatest == other.reachedLatest &&
          isLoadingEarlier == other.isLoadingEarlier &&
          isLoadingLater == other.isLoadingLater &&
          const ListEquality<BookingSummary>().equals(bookings, other.bookings);

  @override
  int get hashCode => Object.hash(
        from,
        to,
        reachedEarliest,
        reachedLatest,
        isLoadingEarlier,
        isLoadingLater,
        const ListEquality<BookingSummary>().hash(bookings),
      );
}
