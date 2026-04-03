import 'package:intl/intl.dart';

/// Represents a single booking entry returned by the finances endpoints.
class FinanceBooking {
  const FinanceBooking({
    required this.id,
    required this.name,
    required this.date,
    this.startTime,
    this.endTime,
    this.venueName,
    this.venueAddress,
    this.status,
    this.price,
    this.amountPaid,
    this.amountDue,
    required this.isPaid,
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
      date: json['date'] as String,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
      status: json['status'] as String?,
      price: json['price'] as String?,
      amountPaid: json['amount_paid'] as String?,
      amountDue: json['amount_due'] as String?,
      isPaid: (json['is_paid'] as bool?) ?? false,
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
  String toString() => 'FinanceBooking(id: $id, name: $name, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceBooking &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
