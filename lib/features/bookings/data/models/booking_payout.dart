import 'package:intl/intl.dart';

String _money(num v) => NumberFormat.currency(symbol: r'$').format(v);

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

class PayoutConfigRef {
  PayoutConfigRef({required this.id, required this.name, required this.isActive});
  final int id;
  final String name;
  final bool isActive;

  factory PayoutConfigRef.fromJson(Map<String, dynamic> j) => PayoutConfigRef(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        isActive: (j['is_active'] as bool?) ?? false,
      );
}

class MemberPayout {
  MemberPayout({
    required this.name,
    this.role,
    required this.amount,
    this.userId,
    this.eventsAttended,
    this.totalEvents,
  });
  final String name;
  final String? role;
  final double amount;
  final int? userId;
  final int? eventsAttended;
  final int? totalEvents;

  String get displayAmount => _money(amount);
  String? get attendanceLabel =>
      (eventsAttended != null && totalEvents != null) ? '$eventsAttended/$totalEvents' : null;

  factory MemberPayout.fromJson(Map<String, dynamic> j) => MemberPayout(
        name: j['name'] as String? ?? (j['user_name'] as String? ?? ''),
        role: j['role'] as String?,
        amount: _toDouble(j['amount']),
        userId: (j['user_id'] as num?)?.toInt(),
        eventsAttended: (j['events_attended'] as num?)?.toInt(),
        totalEvents: (j['total_events'] as num?)?.toInt(),
      );
}

class PayoutGroup {
  PayoutGroup({required this.groupName, required this.total, required this.members});
  final String groupName;
  final double total;
  final List<MemberPayout> members;

  String get displayTotal => _money(total);

  factory PayoutGroup.fromJson(Map<String, dynamic> j) => PayoutGroup(
        groupName: j['group_name'] as String? ?? '',
        total: _toDouble(j['total']),
        members: (j['payouts'] is List)
            ? (j['payouts'] as List).map((e) => MemberPayout.fromJson(e as Map<String, dynamic>)).toList()
            : <MemberPayout>[],
      );
}

class PayoutAdjustment {
  PayoutAdjustment({required this.id, required this.amount, required this.description, this.notes});
  final int id;
  final double amount;
  final String description;
  final String? notes;

  String get displayAmount {
    final s = _money(amount.abs());
    return amount < 0 ? '-$s' : s;
  }

  factory PayoutAdjustment.fromJson(Map<String, dynamic> j) => PayoutAdjustment(
        id: (j['id'] as num).toInt(),
        amount: _toDouble(j['amount']),
        description: j['description'] as String? ?? '',
        notes: j['notes'] as String?,
      );
}

class PayoutEventMember {
  PayoutEventMember({required this.id, this.userId, required this.name, required this.attendanceStatus});
  final int id;
  final int? userId;
  final String name;
  final String attendanceStatus;

  factory PayoutEventMember.fromJson(Map<String, dynamic> j) => PayoutEventMember(
        id: (j['id'] as num).toInt(),
        userId: (j['user_id'] as num?)?.toInt(),
        name: j['name'] as String? ?? '',
        attendanceStatus: j['attendance_status'] as String? ?? 'confirmed',
      );
}

class PayoutEvent {
  PayoutEvent({required this.id, required this.label, required this.value, required this.members});
  final int id;
  final String label;
  final double value;
  final List<PayoutEventMember> members;

  String get displayValue => _money(value);

  factory PayoutEvent.fromJson(Map<String, dynamic> j) => PayoutEvent(
        id: (j['id'] as num).toInt(),
        label: j['label'] as String? ?? '',
        value: _toDouble(j['value']),
        members: (j['members'] is List)
            ? (j['members'] as List).map((e) => PayoutEventMember.fromJson(e as Map<String, dynamic>)).toList()
            : <PayoutEventMember>[],
      );
}

class BookingPayout {
  BookingPayout({
    required this.basePrice,
    required this.adjustedTotal,
    required this.bandCut,
    required this.distributable,
    required this.config,
    required this.availableConfigs,
    required this.members,
    required this.groups,
    required this.adjustments,
    required this.events,
  });

  final double basePrice;
  final double adjustedTotal;
  final double bandCut;
  final double distributable;
  final PayoutConfigRef? config;
  final List<PayoutConfigRef> availableConfigs;
  final List<MemberPayout> members;
  final List<PayoutGroup> groups;
  final List<PayoutAdjustment> adjustments;
  final List<PayoutEvent> events;

  bool get hasAdjustments => adjustments.isNotEmpty;
  String get displayBasePrice => _money(basePrice);
  String get displayAdjustedTotal => _money(adjustedTotal);
  String get displayBandCut => _money(bandCut);
  String get displayDistributable => _money(distributable);

  // Net signed delta from adjustments (adjustedTotal - basePrice).
  // Negative when adjustments reduce the total, positive when they add to it.
  double get adjustmentDelta => adjustedTotal - basePrice;

  // Signed display string: negative → "-$250.00", positive → "+$250.00".
  // Matches the sign idiom used by PayoutAdjustment.displayAmount and adds
  // an explicit "+" prefix on positive deltas for clarity in the summary row.
  String get displayAdjustmentDelta {
    final abs = _money(adjustmentDelta.abs());
    if (adjustmentDelta < 0) return '-$abs';
    if (adjustmentDelta > 0) return '+$abs';
    return abs; // zero: no sign prefix
  }

  factory BookingPayout.fromJson(Map<String, dynamic> json) {
    final payout = (json['payout'] as Map<String, dynamic>?) ?? const {};
    final result = json['result'] as Map<String, dynamic>?;

    List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) f) =>
        raw is List ? raw.map((e) => f(e as Map<String, dynamic>)).toList() : <T>[];

    return BookingPayout(
      basePrice: _toDouble(payout['base_amount']),
      adjustedTotal: _toDouble(payout['adjusted_amount']),
      bandCut: _toDouble(result?['band_cut']),
      distributable: _toDouble(result?['distributable_amount']),
      config: json['config'] is Map
          ? PayoutConfigRef.fromJson(json['config'] as Map<String, dynamic>)
          : null,
      availableConfigs: list(json['available_configs'], PayoutConfigRef.fromJson),
      members: list(result?['member_payouts'], MemberPayout.fromJson),
      groups: list(result?['payment_group_payouts'], PayoutGroup.fromJson),
      adjustments: list(json['adjustments'], PayoutAdjustment.fromJson),
      events: list(json['events'], PayoutEvent.fromJson),
    );
  }
}
