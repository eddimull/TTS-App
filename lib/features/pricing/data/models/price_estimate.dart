import 'json_num.dart';

class PriceBreakdownLine {
  const PriceBreakdownLine({
    required this.key,
    required this.label,
    required this.type,
    this.factor,
    required this.amount,
  });

  final String key;
  final String label;

  /// 'base' | 'multiplier' | 'fee'
  final String type;
  final double? factor;
  final double amount;

  factory PriceBreakdownLine.fromJson(Map<String, dynamic> json) =>
      PriceBreakdownLine(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        factor: parseDouble(json['factor']),
        amount: parseDouble(json['amount']) ?? 0,
      );
}

class PriceWarning {
  const PriceWarning({required this.code, required this.message});

  final String code;
  final String message;

  factory PriceWarning.fromJson(Map<String, dynamic> json) => PriceWarning(
        code: json['code']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
      );
}

class PriceComparable {
  const PriceComparable({
    required this.bookingId,
    required this.name,
    this.date,
    this.price,
    this.venueName,
  });

  final int bookingId;
  final String name;
  final String? date;
  final double? price;
  final String? venueName;

  factory PriceComparable.fromJson(Map<String, dynamic> json) =>
      PriceComparable(
        bookingId: parseInt(json['booking_id']) ?? 0,
        name: json['name']?.toString() ?? '',
        date: json['date']?.toString(),
        price: parseDouble(json['price']),
        venueName: json['venue_name']?.toString(),
      );
}

class PriceEstimate {
  const PriceEstimate({
    this.estimate,
    this.low,
    this.high,
    this.confidence = 'low',
    this.baselineSource,
    this.sampleSize = 0,
    this.baseline,
    this.durationHours,
    this.distanceMiles,
    this.breakdown = const [],
    this.warnings = const [],
    this.comparables = const [],
  });

  /// Null when the backend has no baseline (warning code `no_baseline`).
  final double? estimate;
  final double? low;
  final double? high;

  /// 'high' | 'medium' | 'low'
  final String confidence;

  /// 'manual' | 'history' | 'band_average'
  final String? baselineSource;
  final int sampleSize;
  final double? baseline;
  final double? durationHours;
  final double? distanceMiles;
  final List<PriceBreakdownLine> breakdown;
  final List<PriceWarning> warnings;
  final List<PriceComparable> comparables;

  bool get hasEstimate => estimate != null;

  factory PriceEstimate.fromJson(Map<String, dynamic> json) => PriceEstimate(
        estimate: parseDouble(json['estimate']),
        low: parseDouble(json['low']),
        high: parseDouble(json['high']),
        confidence: json['confidence']?.toString() ?? 'low',
        baselineSource: json['baseline_source']?.toString(),
        sampleSize: parseInt(json['sample_size']) ?? 0,
        baseline: parseDouble(json['baseline']),
        durationHours: parseDouble(json['duration_hours']),
        distanceMiles: parseDouble(json['distance_miles']),
        breakdown:
            asMapList(json['breakdown']).map(PriceBreakdownLine.fromJson).toList(),
        warnings:
            asMapList(json['warnings']).map(PriceWarning.fromJson).toList(),
        comparables: asMapList(json['comparables'])
            .map(PriceComparable.fromJson)
            .toList(),
      );
}

/// Request body for POST price-estimate.
class PriceEstimateRequest {
  const PriceEstimateRequest({
    required this.eventTypeId,
    required this.date,
    this.startTime,
    this.endTime,
    this.durationHours,
    this.venueAddress,
    this.distanceMiles,
    this.addOns = const [],
  });

  final int eventTypeId;

  /// ISO date, e.g. 2027-05-15.
  final String date;
  final String? startTime;
  final String? endTime;
  final double? durationHours;
  final String? venueAddress;
  final double? distanceMiles;
  final List<String> addOns;

  Map<String, dynamic> toJson() => {
        'event_type_id': eventTypeId,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'duration_hours': durationHours,
        'venue_address': (venueAddress == null || venueAddress!.trim().isEmpty)
            ? null
            : venueAddress!.trim(),
        'distance_miles': distanceMiles,
        'add_ons': addOns,
      };
}
