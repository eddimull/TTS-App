/// One payment still owed on a confirmed, contracted booking. The backend
/// decides its group and status; the app only presents them.
class DuePayment {
  const DuePayment({
    required this.bookingId,
    required this.bandId,
    required this.bookingName,
    required this.type,
    required this.status,
    required this.amount,
    required this.dueDate,
    required this.eventDate,
    required this.depositType,
    required this.depositValue,
    required this.depositAmount,
    required this.amountPaid,
    this.daysLate,
    this.overdueSince,
  });

  final int bookingId;
  final int bandId;
  final String bookingName;

  /// 'deposit' or 'balance'.
  final String type;

  /// 'upcoming', 'due_now' or 'overdue'.
  final String status;
  final double amount;
  final String dueDate;
  final String eventDate;
  final String depositType;
  final String depositValue;
  final double depositAmount;
  final double amountPaid;
  final int? daysLate;
  final String? overdueSince;

  bool get isDeposit => type == 'deposit';
  bool get isOverdue => status == 'overdue';
  bool get isDueNow => status == 'due_now';

  factory DuePayment.fromJson(Map<String, dynamic> json) => DuePayment(
        bookingId: (json['booking_id'] as num).toInt(),
        bandId: (json['band_id'] as num).toInt(),
        bookingName: json['booking_name']?.toString() ?? '',
        type: json['type']?.toString() ?? 'balance',
        status: json['status']?.toString() ?? 'upcoming',
        amount: _money(json['amount']),
        dueDate: json['due_date']?.toString() ?? '',
        eventDate: json['event_date']?.toString() ?? '',
        depositType: json['deposit_type']?.toString() ?? 'percent',
        depositValue: json['deposit_value']?.toString() ?? '50.00',
        depositAmount: _money(json['deposit_amount']),
        amountPaid: _money(json['amount_paid']),
        daysLate: (json['days_late'] as num?)?.toInt(),
        overdueSince: json['overdue_since'] as String?,
      );
}

double _money(Object? value) => double.tryParse(value?.toString() ?? '') ?? 0;

class DueGroup {
  const DueGroup({required this.total, required this.payments});

  final double total;
  final List<DuePayment> payments;

  int get count => payments.length;
  bool get isEmpty => payments.isEmpty;

  factory DueGroup.fromJson(Object? summary, Object? rows) {
    final payments = rows is List
        ? rows.cast<Map<String, dynamic>>().map(DuePayment.fromJson).toList()
        : <DuePayment>[];
    final total = summary is Map<String, dynamic> ? _money(summary['total']) : 0.0;
    return DueGroup(total: total, payments: payments);
  }
}

class PaymentsDue {
  const PaymentsDue({
    required this.overdue,
    required this.next30,
    required this.later,
    required this.older,
  });

  final DueGroup overdue;
  final DueGroup next30;
  final DueGroup later;
  final DueGroup older;

  bool get isEmpty =>
      overdue.isEmpty && next30.isEmpty && later.isEmpty && older.isEmpty;

  factory PaymentsDue.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final groups = json['groups'];
    DueGroup group(String key) => DueGroup.fromJson(
          summary is Map<String, dynamic> ? summary[key] : null,
          groups is Map<String, dynamic> ? groups[key] : null,
        );
    return PaymentsDue(
      overdue: group('overdue'),
      next30: group('next_30'),
      later: group('later'),
      older: group('older'),
    );
  }
}
