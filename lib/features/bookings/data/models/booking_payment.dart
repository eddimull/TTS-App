import 'package:intl/intl.dart';

class BookingPayment {
  final int id;
  final String name;

  /// Raw amount string, e.g. "1500.00" — no commas.
  final String amount;

  final String? date;
  final String? paymentType;
  final String? status;

  const BookingPayment({
    required this.id,
    required this.name,
    required this.amount,
    this.date,
    this.paymentType,
    this.status,
  });

  String get displayAmount {
    final v = double.tryParse(amount);
    if (v == null) return amount;
    return NumberFormat.currency(symbol: r'$').format(v);
  }

  String get displayPaymentType {
    switch (paymentType) {
      case 'cash':
        return 'Cash';
      case 'check':
        return 'Check';
      case 'credit_card':
        return 'Credit Card';
      case 'venmo':
        return 'Venmo';
      case 'zelle':
        return 'Zelle';
      case 'wire':
        return 'Wire Transfer';
      case 'invoice':
        return 'Invoice';
      case 'portal':
        return 'Client Portal';
      default:
        return 'Other';
    }
  }

  factory BookingPayment.fromJson(Map<String, dynamic> json) => BookingPayment(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        amount: json['amount'] as String? ?? '0.00',
        date: json['date'] as String?,
        paymentType: json['payment_type'] as String?,
        status: json['status'] as String?,
      );
}
