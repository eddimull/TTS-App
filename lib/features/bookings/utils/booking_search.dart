import '../data/models/booking_summary.dart';

/// Returns true if [booking] matches [query] (case-insensitive contains)
/// against any of: name, venue name, or any contact's name/email/phone.
///
/// Empty or whitespace-only queries match everything.
bool bookingMatchesQuery(BookingSummary booking, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;

  if (booking.name.toLowerCase().contains(q)) return true;
  final venue = booking.venueName;
  if (venue != null && venue.toLowerCase().contains(q)) return true;

  for (final c in booking.contacts) {
    if (c.name.toLowerCase().contains(q)) return true;
    final email = c.email;
    if (email != null && email.toLowerCase().contains(q)) return true;
    final phone = c.phone;
    if (phone != null && phone.toLowerCase().contains(q)) return true;
  }
  return false;
}
