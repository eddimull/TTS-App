import 'package:intl/intl.dart';
import 'booking_contact.dart';

class BookingSummary {
  const BookingSummary({
    required this.id,
    required this.name,
    required this.date,
    this.startTime,
    this.endTime,
    this.venueName,
    this.venueAddress,
    this.status,
    this.price,
    this.eventTypeId,
    this.notes,
    this.amountPaid,
    this.amountDue,
    required this.isPaid,
    required this.contacts,
  });

  final int id;
  final String name;

  /// ISO date string, e.g. "2026-05-15".
  final String date;

  final String? startTime;
  final String? endTime;
  final String? venueName;
  final String? venueAddress;
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

  factory BookingSummary.fromJson(Map<String, dynamic> json) {
    final rawContacts = json['contacts'];
    final contacts = rawContacts is List
        ? rawContacts
            .cast<Map<String, dynamic>>()
            .map(BookingContact.fromJson)
            .toList()
        : <BookingContact>[];

    return BookingSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      date: json['date'] as String,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
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
    );
  }

  /// Parses [date] into a [DateTime]. Returns [DateTime.now()] as a fallback.
  DateTime get parsedDate {
    try {
      return DateTime.parse(date);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Formats [price] as a currency string, e.g. "$3,500.00".
  /// Returns [price] as-is if it cannot be parsed, or "—" if null.
  String get displayPrice {
    if (price == null) return '—';
    final parsed = double.tryParse(price!);
    if (parsed == null) return price!;
    return NumberFormat.currency(symbol: '\$').format(parsed);
  }

  @override
  String toString() => 'BookingSummary(id: $id, name: $name, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingSummary &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
