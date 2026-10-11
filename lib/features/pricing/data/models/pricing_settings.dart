import 'json_num.dart';

class AddOn {
  const AddOn({required this.key, required this.label, required this.amount});

  final String key;
  final String label;
  final double amount;

  AddOn copyWith({String? key, String? label, double? amount}) => AddOn(
        key: key ?? this.key,
        label: label ?? this.label,
        amount: amount ?? this.amount,
      );

  factory AddOn.fromJson(Map<String, dynamic> json) => AddOn(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        amount: parseDouble(json['amount']) ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'key': key, 'label': label, 'amount': amount};
}

class SpecialDate {
  const SpecialDate(
      {required this.date, required this.label, required this.multiplier});

  /// `MM-DD` (recurring) or `YYYY-MM-DD` (one-off).
  final String date;
  final String label;
  final double multiplier;

  SpecialDate copyWith({String? date, String? label, double? multiplier}) =>
      SpecialDate(
        date: date ?? this.date,
        label: label ?? this.label,
        multiplier: multiplier ?? this.multiplier,
      );

  factory SpecialDate.fromJson(Map<String, dynamic> json) => SpecialDate(
        date: json['date']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        multiplier: parseDouble(json['multiplier']) ?? 1.0,
      );

  Map<String, dynamic> toJson() =>
      {'date': date, 'label': label, 'multiplier': multiplier};
}

class PricingSettings {
  const PricingSettings({
    this.seasonMultipliers = const {},
    this.dayOfWeekMultipliers = const {},
    this.specialDates = const [],
    this.standardHours = 4,
    this.standardHoursByType = const {},
    this.overtimePctPerHour = 15,
    this.minDurationFactor = 0.75,
    this.shortNoticeDays = 30,
    this.shortNoticeMultiplier = 1.0,
    this.annualIncreasePct = 3,
    this.freeRadiusMiles = 50,
    this.perMileRate = 2.0,
    this.lodgingThresholdMiles = 150,
    this.lodgingFee = 0,
    this.addOns = const [],
    this.baseRates = const {},
    this.roundTo = 50,
  });

  /// Keyed by month 1..12.
  final Map<int, double> seasonMultipliers;

  /// Keyed by weekday 0..6 (0 = Sunday).
  final Map<int, double> dayOfWeekMultipliers;
  final List<SpecialDate> specialDates;
  final double standardHours;
  final Map<int, double> standardHoursByType;
  final double overtimePctPerHour;
  final double minDurationFactor;
  final int shortNoticeDays;
  final double shortNoticeMultiplier;
  final double annualIncreasePct;
  final double freeRadiusMiles;
  final double perMileRate;
  final double lodgingThresholdMiles;
  final double lodgingFee;
  final List<AddOn> addOns;

  /// Manual base-rate overrides keyed by event type id.
  final Map<int, double> baseRates;
  final double roundTo;

  static Map<int, double> _intDoubleMap(Object? raw) {
    final out = <int, double>{};
    asMap(raw).forEach((k, v) {
      final key = int.tryParse(k);
      final val = parseDouble(v);
      if (key != null && val != null) out[key] = val;
    });
    return out;
  }

  factory PricingSettings.fromJson(Map<String, dynamic> json) =>
      PricingSettings(
        seasonMultipliers: _intDoubleMap(json['season_multipliers']),
        dayOfWeekMultipliers: _intDoubleMap(json['day_of_week_multipliers']),
        specialDates:
            asMapList(json['special_dates']).map(SpecialDate.fromJson).toList(),
        standardHours: parseDouble(json['standard_hours']) ?? 4,
        standardHoursByType: _intDoubleMap(json['standard_hours_by_type']),
        overtimePctPerHour: parseDouble(json['overtime_pct_per_hour']) ?? 15,
        minDurationFactor: parseDouble(json['min_duration_factor']) ?? 0.75,
        shortNoticeDays: parseInt(json['short_notice_days']) ?? 30,
        shortNoticeMultiplier:
            parseDouble(json['short_notice_multiplier']) ?? 1.0,
        annualIncreasePct: parseDouble(json['annual_increase_pct']) ?? 3,
        freeRadiusMiles: parseDouble(json['free_radius_miles']) ?? 50,
        perMileRate: parseDouble(json['per_mile_rate']) ?? 2.0,
        lodgingThresholdMiles:
            parseDouble(json['lodging_threshold_miles']) ?? 150,
        lodgingFee: parseDouble(json['lodging_fee']) ?? 0,
        addOns: asMapList(json['add_ons']).map(AddOn.fromJson).toList(),
        baseRates: _intDoubleMap(json['base_rates']),
        roundTo: parseDouble(json['round_to']) ?? 50,
      );

  Map<String, dynamic> toJson() => {
        'season_multipliers':
            seasonMultipliers.map((k, v) => MapEntry('$k', v)),
        'day_of_week_multipliers':
            dayOfWeekMultipliers.map((k, v) => MapEntry('$k', v)),
        'special_dates': specialDates.map((e) => e.toJson()).toList(),
        'standard_hours': standardHours,
        'standard_hours_by_type':
            standardHoursByType.map((k, v) => MapEntry('$k', v)),
        'overtime_pct_per_hour': overtimePctPerHour,
        'min_duration_factor': minDurationFactor,
        'short_notice_days': shortNoticeDays,
        'short_notice_multiplier': shortNoticeMultiplier,
        'annual_increase_pct': annualIncreasePct,
        'free_radius_miles': freeRadiusMiles,
        'per_mile_rate': perMileRate,
        'lodging_threshold_miles': lodgingThresholdMiles,
        'lodging_fee': lodgingFee,
        'add_ons': addOns.map((e) => e.toJson()).toList(),
        'base_rates': baseRates.map((k, v) => MapEntry('$k', v)),
        'round_to': roundTo,
      };

  PricingSettings copyWith({
    Map<int, double>? seasonMultipliers,
    Map<int, double>? dayOfWeekMultipliers,
    List<SpecialDate>? specialDates,
    double? standardHours,
    Map<int, double>? standardHoursByType,
    double? overtimePctPerHour,
    double? minDurationFactor,
    int? shortNoticeDays,
    double? shortNoticeMultiplier,
    double? annualIncreasePct,
    double? freeRadiusMiles,
    double? perMileRate,
    double? lodgingThresholdMiles,
    double? lodgingFee,
    List<AddOn>? addOns,
    Map<int, double>? baseRates,
    double? roundTo,
  }) =>
      PricingSettings(
        seasonMultipliers: seasonMultipliers ?? this.seasonMultipliers,
        dayOfWeekMultipliers: dayOfWeekMultipliers ?? this.dayOfWeekMultipliers,
        specialDates: specialDates ?? this.specialDates,
        standardHours: standardHours ?? this.standardHours,
        standardHoursByType: standardHoursByType ?? this.standardHoursByType,
        overtimePctPerHour: overtimePctPerHour ?? this.overtimePctPerHour,
        minDurationFactor: minDurationFactor ?? this.minDurationFactor,
        shortNoticeDays: shortNoticeDays ?? this.shortNoticeDays,
        shortNoticeMultiplier:
            shortNoticeMultiplier ?? this.shortNoticeMultiplier,
        annualIncreasePct: annualIncreasePct ?? this.annualIncreasePct,
        freeRadiusMiles: freeRadiusMiles ?? this.freeRadiusMiles,
        perMileRate: perMileRate ?? this.perMileRate,
        lodgingThresholdMiles:
            lodgingThresholdMiles ?? this.lodgingThresholdMiles,
        lodgingFee: lodgingFee ?? this.lodgingFee,
        addOns: addOns ?? this.addOns,
        baseRates: baseRates ?? this.baseRates,
        roundTo: roundTo ?? this.roundTo,
      );
}

class PricingEventType {
  const PricingEventType({required this.id, required this.name});
  final int id;
  final String name;

  factory PricingEventType.fromJson(Map<String, dynamic> json) =>
      PricingEventType(
        id: parseInt(json['id']) ?? 0,
        name: json['name']?.toString() ?? '',
      );
}

class PricingHistoryEntry {
  const PricingHistoryEntry({
    required this.eventTypeId,
    required this.sampleSize,
    this.baseline,
  });

  final int eventTypeId;
  final int sampleSize;
  final double? baseline;

  factory PricingHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PricingHistoryEntry(
        eventTypeId: parseInt(json['event_type_id']) ?? 0,
        sampleSize: parseInt(json['sample_size']) ?? 0,
        baseline: parseDouble(json['baseline']),
      );
}

/// Response of GET/PUT pricing-settings.
class PricingSettingsBundle {
  const PricingSettingsBundle({
    required this.settings,
    this.eventTypes = const [],
    this.history = const [],
  });

  final PricingSettings settings;
  final List<PricingEventType> eventTypes;
  final List<PricingHistoryEntry> history;

  PricingHistoryEntry? historyFor(int eventTypeId) {
    for (final h in history) {
      if (h.eventTypeId == eventTypeId) return h;
    }
    return null;
  }

  factory PricingSettingsBundle.fromJson(Map<String, dynamic> json) =>
      PricingSettingsBundle(
        settings: PricingSettings.fromJson(asMap(json['settings'])),
        eventTypes: asMapList(json['event_types'])
            .map(PricingEventType.fromJson)
            .toList(),
        history: asMapList(json['history'])
            .map(PricingHistoryEntry.fromJson)
            .toList(),
      );
}
