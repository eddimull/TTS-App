import 'package:flutter/cupertino.dart';

/// Pairs a [BookingDateStatus] with the title of the highest-priority booking
/// on that date.  Used by [BookingCalendarPicker] to show a booking name when
/// the user selects a date that already has a booking.
class BookingDateInfo {
  const BookingDateInfo({
    required this.status,
    required this.bookingTitle,
  });

  final BookingDateStatus status;

  /// Human-readable name of the booking, e.g. "The Grand Wedding".
  final String bookingTitle;
}

/// The booking occupancy status for a single calendar day.
///
/// Used by [BookingCalendarPicker] to colour-code day cells.
enum BookingDateStatus {
  /// A confirmed booking exists on this date — date is taken / unavailable.
  confirmed,

  /// A booking with a pending contract exists on this date.
  pending,

  /// A draft booking exists on this date.
  draft;

  /// Higher value = higher priority when multiple bookings share a date.
  int get priority => switch (this) {
        BookingDateStatus.confirmed => 3,
        BookingDateStatus.pending => 2,
        BookingDateStatus.draft => 1,
      };

  /// Background fill colour for the calendar day cell.
  Color cellColor(BuildContext context) => switch (this) {
        // Confirmed: red tint — date is taken.
        BookingDateStatus.confirmed =>
          CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.15),
        // Pending: yellow — contract in progress.
        BookingDateStatus.pending =>
          CupertinoColors.systemYellow.resolveFrom(context).withValues(alpha: 0.30),
        // Draft: blue — booking started but not submitted.
        BookingDateStatus.draft =>
          CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.15),
      };

  /// Foreground / accent colour for the day number and indicator dot.
  Color accentColor(BuildContext context) => switch (this) {
        BookingDateStatus.confirmed =>
          CupertinoColors.systemRed.resolveFrom(context),
        BookingDateStatus.pending =>
          CupertinoColors.systemYellow.resolveFrom(context),
        BookingDateStatus.draft =>
          CupertinoColors.systemBlue.resolveFrom(context),
      };

  /// Whether to render a strikethrough line over the day number.
  bool get showStrikethrough => this == BookingDateStatus.confirmed;
}
