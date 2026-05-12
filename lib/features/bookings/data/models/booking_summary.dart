import 'package:intl/intl.dart';
import '../../../auth/data/models/band_summary.dart';
import '../../../events/data/models/event_summary.dart';
import 'booking_contact.dart';

class BookingSummary {
  const BookingSummary({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.eventCount,
    required this.isMultiEvent,
    this.venueSummary,
    this.status,
    this.price,
    this.eventTypeId,
    this.notes,
    this.amountPaid,
    this.amountDue,
    required this.isPaid,
    required this.contacts,
    this.events = const [],
    this.band,
  });

  final int id;
  final String name;

  /// ISO date string of the chronologically-first event, e.g. "2026-05-15".
  final String startDate;

  /// ISO date string of the chronologically-last event. Equals [startDate]
  /// for single-event bookings.
  final String endDate;

  final int eventCount;

  /// True iff `eventCount > 1`.
  final bool isMultiEvent;

  /// Display-ready summary of the booking's venue(s): primary event's venue
  /// name when consistent, "Multiple venues" otherwise. Null if no event has
  /// a venue.
  final String? venueSummary;

  final String? status;

  /// Raw price string from the API, e.g. "3500.00".
  final String? price;

  final int? eventTypeId;
  final String? notes;

  /// Raw amount-paid string, e.g. "1000.00".
  final String? amountPaid;

  /// Raw amount-due string, e.g. "2500.00".
  final String? amountDue;

  final bool isPaid;
  final List<BookingContact> contacts;

  /// Lightweight per-event records for filter/subtitle rendering. The list
  /// endpoint emits this with just `date`, `title`, `start_time`, etc. —
  /// enough for any-event-in-range filtering and the multi-event subtitle.
  final List<EventSummary> events;

  /// Optional nested band identity. Present on `/me/bookings` and per-band
  /// `/bookings` responses; absent on legacy cached payloads.
  final BandSummary? band;

  factory BookingSummary.fromJson(Map<String, dynamic> json) {
    final rawContacts = json['contacts'];
    final contacts = rawContacts is List
        ? rawContacts
            .cast<Map<String, dynamic>>()
            .map(BookingContact.fromJson)
            .toList()
        : <BookingContact>[];

    final rawEvents = json['events'];
    final events = rawEvents is List
        ? rawEvents
            .cast<Map<String, dynamic>>()
            .map(EventSummary.fromJson)
            .toList()
        : <EventSummary>[];

    final rawBand = json['band'];
    final band = rawBand is Map<String, dynamic>
        ? BandSummary.fromJson(rawBand)
        : null;

    return BookingSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      startDate: (json['start_date'] as String?) ?? '',
      endDate: (json['end_date'] as String?) ?? '',
      eventCount: (json['event_count'] as num?)?.toInt() ?? 0,
      isMultiEvent: (json['is_multi_event'] as bool?) ?? false,
      venueSummary: json['venue_summary'] as String?,
      status: json['status'] as String?,
      price: json['price'] as String?,
      eventTypeId: json['event_type_id'] == null
          ? null
          : (json['event_type_id'] as num).toInt(),
      notes: json['notes'] as String?,
      amountPaid: json['amount_paid'] as String?,
      amountDue: json['amount_due'] as String?,
      isPaid: (json['is_paid'] as bool?) ?? false,
      contacts: contacts,
      events: events,
      band: band,
    );
  }

  /// Parses [startDate] into a [DateTime]. Returns [DateTime.now()] as a
  /// fallback (rare — payload should always include start_date).
  DateTime get parsedStartDate {
    try {
      return DateTime.parse(startDate);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// "May 13" for single-event, "May 13–17" for multi-event same-month,
  /// "May 13 – Jun 2" for cross-month. Used by the list subtitle.
  String get displayDateRange {
    final start = parsedStartDate;
    if (!isMultiEvent || startDate == endDate) {
      return DateFormat('MMM d').format(start);
    }
    DateTime end;
    try {
      end = DateTime.parse(endDate);
    } catch (_) {
      return DateFormat('MMM d').format(start);
    }
    if (start.month == end.month && start.year == end.year) {
      return '${DateFormat('MMM d').format(start)}–${DateFormat('d').format(end)}';
    }
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(end)}';
  }

  /// Formats [price] as a currency string, e.g. "$3,500.00".
  String get displayPrice {
    if (price == null) return r'$0.00';
    final parsed = double.tryParse(price!);
    if (parsed == null) return price!;
    return NumberFormat.currency(symbol: '\$').format(parsed);
  }

  @override
  String toString() =>
      'BookingSummary(id: $id, name: $name, startDate: $startDate, events: $eventCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
