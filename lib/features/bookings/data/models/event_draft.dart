/// Lightweight create-only DTO for adding a new event under a booking.
///
/// Has no `id` / `key` because the event doesn't exist yet. Used by:
/// - `BookingsRepository.createBooking` (the initial event for a new booking)
/// - `BookingsRepository.addEventToBooking` (adding an event to an existing
///    booking)
///
/// For mutating an existing event, see `EventsRepository.updateEvent`.
class EventDraft {
  const EventDraft({
    required this.title,
    required this.date,
    this.startTime,
    this.endTime,
    this.venueName,
    this.venueAddress,
    this.price,
  });

  final String title;

  /// ISO date string, e.g. "2026-05-15".
  final String date;

  /// HH:mm, e.g. "19:00", or null.
  final String? startTime;

  /// HH:mm, e.g. "22:00", or null.
  final String? endTime;

  final String? venueName;
  final String? venueAddress;

  /// Per-event price string, e.g. "1500.00", or null.
  final String? price;

  Map<String, dynamic> toJson() => {
        'title': title,
        'date': date,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        if (venueName != null) 'venue_name': venueName,
        if (venueAddress != null) 'venue_address': venueAddress,
        if (price != null) 'price': price,
      };
}
