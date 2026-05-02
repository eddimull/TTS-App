enum BookingConfirmation { confirmed, pending, cancelled }

/// Normalises the free-form `status` string from the API into one of three
/// rendering buckets used by the dashboard calendar markers.
///
/// - Anything containing "cancel" (case-insensitive) → cancelled.
/// - "confirmed", "booked", or "accepted" → confirmed.
/// - Everything else (including null and empty) → pending.
BookingConfirmation bookingConfirmationFromStatus(String? status) {
  final s = (status ?? '').toLowerCase().trim();
  if (s.contains('cancel')) return BookingConfirmation.cancelled;
  if (s == 'confirmed' || s == 'booked' || s == 'accepted') {
    return BookingConfirmation.confirmed;
  }
  return BookingConfirmation.pending;
}
