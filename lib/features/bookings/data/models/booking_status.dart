/// Status filter applied to the Bookings list.
///
/// `all` is the no-filter sentinel — selecting it shows every booking.
enum BookingStatus { all, confirmed, pending, draft }

extension BookingStatusLabel on BookingStatus {
  String get label => switch (this) {
        BookingStatus.all => 'All',
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.pending => 'Pending',
        BookingStatus.draft => 'Draft',
      };

  /// Lowercase API-style key, used to compare against `BookingSummary.status`.
  String? get apiKey => switch (this) {
        BookingStatus.all => null,
        BookingStatus.confirmed => 'confirmed',
        BookingStatus.pending => 'pending',
        BookingStatus.draft => 'draft',
      };
}
