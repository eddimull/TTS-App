import 'package:intl/intl.dart';

/// Represents a single booking entry returned by the finances endpoints.
///
/// The payload mirrors [BookingSummary]'s multi-event shape: a booking spans
/// a date range (`start_date`..`end_date`) with a `venue_summary` aggregated
/// across its events.
class FinanceBooking {
  const FinanceBooking({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.eventCount,
    required this.isMultiEvent,
    this.venueSummary,
    this.status,
    this.price,
    this.amountPaid,
    this.amountDue,
    required this.isPaid,
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

  /// Raw price string from the API, e.g. "1500.00".
  final String? price;

  /// Raw amount-paid string, e.g. "500.00".
  final String? amountPaid;

  /// Raw amount-due string, e.g. "1000.00".
  final String? amountDue;

  final bool isPaid;

  factory FinanceBooking.fromJson(Map<String, dynamic> json) {
    return FinanceBooking(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      startDate: (json['start_date'] as String?) ?? '',
      endDate: (json['end_date'] as String?) ?? '',
      eventCount: (json['event_count'] as num?)?.toInt() ?? 0,
      isMultiEvent: (json['is_multi_event'] as bool?) ?? false,
      venueSummary: json['venue_summary'] as String?,
      status: json['status'] as String?,
      price: json['price'] as String?,
      amountPaid: json['amount_paid'] as String?,
      amountDue: json['amount_due'] as String?,
      isPaid: (json['is_paid'] as bool?) ?? false,
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

  /// Card subtitle: "Fri, May 13, 2026" for single-event, "May 13–17, 2026"
  /// for multi-event same-month, "May 13 – Jun 2, 2026" for cross-month.
  String get displayDateRange {
    final start = parsedStartDate;
    if (!isMultiEvent || startDate == endDate) {
      return DateFormat('EEE, MMM d, yyyy').format(start);
    }
    DateTime end;
    try {
      end = DateTime.parse(endDate);
    } catch (_) {
      return DateFormat('EEE, MMM d, yyyy').format(start);
    }
    if (start.month == end.month && start.year == end.year) {
      return '${DateFormat('MMM d').format(start)}–${DateFormat('d, yyyy').format(end)}';
    }
    if (start.year == end.year) {
      return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
    }
    return '${DateFormat('MMM d, yyyy').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
  }

  static final _currencyFormat = NumberFormat.currency(symbol: '\$');

  String _formatCurrency(String? raw) {
    if (raw == null) return '—';
    final parsed = double.tryParse(raw);
    if (parsed == null) return raw;
    return _currencyFormat.format(parsed);
  }

  /// Formats [price] as a currency string, e.g. "$1,500.00".
  String get displayPrice => _formatCurrency(price);

  /// Formats [amountDue] as a currency string, e.g. "$1,000.00".
  String get displayAmountDue => _formatCurrency(amountDue);

  /// Formats [amountPaid] as a currency string, e.g. "$500.00".
  String get displayAmountPaid => _formatCurrency(amountPaid);

  @override
  String toString() =>
      'FinanceBooking(id: $id, name: $name, startDate: $startDate)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceBooking &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
