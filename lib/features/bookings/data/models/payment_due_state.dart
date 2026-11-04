/// Where one payment (deposit or balance) stands, as the backend decides it.
class PaymentDue {
  const PaymentDue({
    required this.owed,
    required this.dueDate,
    required this.status,
    this.overdueSince,
  });

  /// Dollars still owed, e.g. "250.00".
  final String owed;

  /// ISO date.
  final String dueDate;

  /// 'upcoming', 'due_now' or 'overdue'.
  final String status;

  /// ISO date, set only when [status] is 'overdue'.
  final String? overdueSince;

  double get owedAmount => double.tryParse(owed) ?? 0;
  bool get isOverdue => status == 'overdue';
  bool get isDueNow => status == 'due_now';

  factory PaymentDue.fromJson(Map<String, dynamic> json) => PaymentDue(
        owed: json['owed']?.toString() ?? '0.00',
        dueDate: json['due_date']?.toString() ?? '',
        status: json['status']?.toString() ?? 'upcoming',
        overdueSince: json['overdue_since'] as String?,
      );
}

/// A contracted booking's payment state. The backend sends null until the
/// booking is confirmed with a signed contract, when nothing has a due date.
class PaymentDueState {
  const PaymentDueState({
    required this.eventDate,
    required this.deposit,
    required this.balance,
    this.merged = false,
  });

  /// ISO date of the first event.
  final String eventDate;
  final PaymentDue deposit;
  final PaymentDue balance;

  /// Signed so close to the show that the deposit and balance share one
  /// deadline, with [balance] holding the full amount owed.
  final bool merged;

  /// Null when [json] isn't a usable payload, so a malformed response degrades
  /// to "no due dates" instead of breaking the booking screen.
  static PaymentDueState? tryFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final deposit = json['deposit'];
    final balance = json['balance'];
    if (deposit is! Map<String, dynamic> || balance is! Map<String, dynamic>) {
      return null;
    }
    return PaymentDueState(
      eventDate: json['event_date']?.toString() ?? '',
      deposit: PaymentDue.fromJson(deposit),
      balance: PaymentDue.fromJson(balance),
      merged: json['merged'] == true,
    );
  }
}
