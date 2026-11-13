import 'package:intl/intl.dart';

/// A balance the band chose to stop collecting. The booking counts as settled,
/// but [amount] was never received, so it isn't part of the amount paid.
class BalanceWriteOff {
  const BalanceWriteOff({
    required this.amount,
    this.at,
    this.by,
    this.note,
  });

  /// Dollars written off, e.g. "50.00".
  final String amount;

  /// ISO timestamp.
  final String? at;

  /// Name of the band member who wrote it off.
  final String? by;
  final String? note;

  double get amountValue => double.tryParse(amount) ?? 0;

  String get displayAmount =>
      NumberFormat.currency(symbol: r'$').format(amountValue);

  /// Null when [json] isn't a usable payload (absent on older backends).
  static BalanceWriteOff? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final amount = json['amount']?.toString();
    if (amount == null || amount.isEmpty) return null;
    final note = json['note']?.toString();
    return BalanceWriteOff(
      amount: amount,
      at: json['at']?.toString(),
      by: json['by']?.toString(),
      note: (note == null || note.trim().isEmpty) ? null : note,
    );
  }
}
