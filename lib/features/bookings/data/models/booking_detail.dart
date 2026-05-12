import 'package:intl/intl.dart';
import '../../../auth/data/models/band_summary.dart';
import '../../../events/data/models/event_summary.dart';
import 'booking_contact.dart';
import 'booking_contract.dart';
import 'booking_payment.dart';

class BookingDetail {
  const BookingDetail({
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
    required this.events,
    this.contractOption,
    this.contract,
    this.payments = const [],
    this.band,
  });

  final int id;
  final String name;

  /// ISO date string of the chronologically-first event.
  final String startDate;

  /// ISO date string of the chronologically-last event. Equals [startDate]
  /// for single-event bookings.
  final String endDate;

  final int eventCount;
  final bool isMultiEvent;

  /// Display-ready venue summary across all events.
  final String? venueSummary;

  final String? status;
  final String? price;
  final int? eventTypeId;
  final String? notes;
  final String? amountPaid;
  final String? amountDue;
  final bool isPaid;
  final List<BookingContact> contacts;

  /// Full per-event records for the detail screen.
  final List<EventSummary> events;

  /// Contract option: "default", "none", "external", or null.
  final String? contractOption;

  /// The associated contract record, if any.
  final BookingContract? contract;

  /// List of recorded payments for this booking.
  final List<BookingPayment> payments;

  /// Optional nested band identity.
  final BandSummary? band;

  factory BookingDetail.fromJson(Map<String, dynamic> json) {
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

    final rawPayments = json['payments'];
    final payments = rawPayments is List
        ? rawPayments
            .cast<Map<String, dynamic>>()
            .map(BookingPayment.fromJson)
            .toList()
        : <BookingPayment>[];

    final rawContract = json['contract'];
    final contract = rawContract is Map<String, dynamic>
        ? BookingContract.fromJson(rawContract)
        : null;

    final rawBand = json['band'];
    final band = rawBand is Map<String, dynamic>
        ? BandSummary.fromJson(rawBand)
        : null;

    return BookingDetail(
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
      contractOption: json['contract_option'] as String?,
      contract: contract,
      payments: payments,
      band: band,
    );
  }

  DateTime get parsedStartDate {
    try {
      return DateTime.parse(startDate);
    } catch (_) {
      return DateTime.now();
    }
  }

  String get displayPrice {
    if (price == null) return r'$0.00';
    final parsed = double.tryParse(price!);
    if (parsed == null) return price!;
    return NumberFormat.currency(symbol: '\$').format(parsed);
  }

  String get displayAmountPaid {
    if (amountPaid == null) return '—';
    final parsed = double.tryParse(amountPaid!);
    if (parsed == null) return amountPaid!;
    return NumberFormat.currency(symbol: '\$').format(parsed);
  }

  String get displayAmountDue {
    if (amountDue == null) return '—';
    final parsed = double.tryParse(amountDue!);
    if (parsed == null) return amountDue!;
    return NumberFormat.currency(symbol: '\$').format(parsed);
  }

  @override
  String toString() =>
      'BookingDetail(id: $id, name: $name, startDate: $startDate, events: $eventCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingDetail &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
