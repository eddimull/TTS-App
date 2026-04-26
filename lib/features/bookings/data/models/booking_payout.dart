import 'package:intl/intl.dart';

class BookingPayout {
  const BookingPayout({
    required this.totalAmount,
    required this.bandCut,
    this.bandCutDescription,
    required this.distributableAmount,
    this.configurationName,
    this.configurationActive = false,
    this.adjustments = const [],
    this.members = const [],
  });

  /// Raw decimal string from the API, e.g. "6500.00".
  final String totalAmount;

  /// Raw decimal string for the band's cut.
  final String bandCut;

  /// Human-friendly description of how the band cut was computed,
  /// e.g. "Tiered based on amount".
  final String? bandCutDescription;

  /// Raw decimal string for the amount distributable to members.
  final String distributableAmount;

  /// Display name for the active payout configuration, e.g. "full band".
  final String? configurationName;

  /// Whether the configuration is currently active.
  final bool configurationActive;

  final List<BookingPayoutAdjustment> adjustments;
  final List<BookingPayoutMember> members;

  factory BookingPayout.fromJson(Map<String, dynamic> json) {
    final rawAdjustments = json['adjustments'];
    final adjustments = rawAdjustments is List
        ? rawAdjustments
            .cast<Map<String, dynamic>>()
            .map(BookingPayoutAdjustment.fromJson)
            .toList()
        : <BookingPayoutAdjustment>[];

    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers
            .cast<Map<String, dynamic>>()
            .map(BookingPayoutMember.fromJson)
            .toList()
        : <BookingPayoutMember>[];

    final config = json['configuration'];
    final configMap = config is Map<String, dynamic> ? config : null;

    return BookingPayout(
      totalAmount: _asString(json['total_amount']) ?? '0',
      bandCut: _asString(json['band_cut']) ?? '0',
      bandCutDescription: json['band_cut_description'] as String?,
      distributableAmount: _asString(json['distributable_amount']) ?? '0',
      configurationName: configMap?['name'] as String?,
      configurationActive: (configMap?['is_active'] as bool?) ?? false,
      adjustments: adjustments,
      members: members,
    );
  }

  String get displayTotal => _money(totalAmount);
  String get displayBandCut => _money(bandCut);
  String get displayDistributable => _money(distributableAmount);
}

class BookingPayoutAdjustment {
  const BookingPayoutAdjustment({
    required this.id,
    required this.name,
    required this.amount,
    this.type,
  });

  final int id;
  final String name;
  final String amount;
  final String? type;

  factory BookingPayoutAdjustment.fromJson(Map<String, dynamic> json) {
    return BookingPayoutAdjustment(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      amount: _asString(json['amount']) ?? '0',
      type: json['type'] as String?,
    );
  }

  String get displayAmount => _money(amount);
}

class BookingPayoutMember {
  const BookingPayoutMember({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.attendance,
    required this.amount,
    this.isCurrentUser = false,
  });

  final int id;
  final String name;
  final String? role;

  /// e.g. "member" or "substitute".
  final String? type;

  /// e.g. "1/1" — attended/total events for this booking.
  final String? attendance;

  final String amount;

  /// Whether this member row represents the currently signed-in user.
  final bool isCurrentUser;

  factory BookingPayoutMember.fromJson(Map<String, dynamic> json) {
    return BookingPayoutMember(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      role: json['role'] as String?,
      type: json['type'] as String?,
      attendance: json['attendance'] as String?,
      amount: _asString(json['amount']) ?? '0',
      isCurrentUser: (json['is_current_user'] as bool?) ?? false,
    );
  }

  String get displayAmount => _money(amount);
}

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num) return v.toString();
  return v.toString();
}

String _money(String raw) {
  final parsed = double.tryParse(raw);
  if (parsed == null) return raw;
  return NumberFormat.currency(symbol: '\$').format(parsed);
}
