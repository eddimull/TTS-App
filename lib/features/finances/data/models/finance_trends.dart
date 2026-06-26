/// One month's bucketed finance figures. All `*Cents` are in cents.
class TrendMonth {
  const TrendMonth({
    required this.month,
    required this.paidCents,
    required this.unpaidCents,
    required this.forecastCents,
    required this.netCents,
    required this.count,
  });

  final int month; // 1..12
  final int paidCents;
  final int unpaidCents;
  final int forecastCents;
  final int netCents;
  final int count;

  factory TrendMonth.fromJson(Map<String, dynamic> json) {
    int c(String k) => (json[k] as num?)?.toInt() ?? 0;
    return TrendMonth(
      month: c('month'),
      paidCents: c('paid'),
      unpaidCents: c('unpaid'),
      forecastCents: c('forecast'),
      netCents: c('net'),
      count: c('count'),
    );
  }

  bool get isZero =>
      paidCents == 0 && unpaidCents == 0 && forecastCents == 0 && netCents == 0 && count == 0;
}

/// Per-month finance trends for a band+year, optionally with a snapshot and a
/// current (unfiltered) comparison series.
class FinanceTrends {
  const FinanceTrends({
    required this.year,
    required this.snapshotDate,
    required this.availableYears,
    required this.months,
    required this.currentMonths,
  });

  final int year;
  final String? snapshotDate;
  final List<int> availableYears;
  final List<TrendMonth> months;
  final List<TrendMonth>? currentMonths;

  factory FinanceTrends.fromJson(Map<String, dynamic> json) {
    List<TrendMonth> parse(List<dynamic> raw) =>
        raw.cast<Map<String, dynamic>>().map(TrendMonth.fromJson).toList();
    final current = json['current_months'];
    return FinanceTrends(
      year: (json['year'] as num).toInt(),
      snapshotDate: json['snapshot_date'] as String?,
      availableYears: (json['available_years'] as List<dynamic>? ?? const [])
          .cast<num>().map((e) => e.toInt()).toList(),
      months: parse(json['months'] as List<dynamic>? ?? const []),
      currentMonths: current is List ? parse(current) : null,
    );
  }

  bool get comparing => currentMonths != null;

  int get totalPaidCents => months.fold(0, (s, m) => s + m.paidCents);
  int get totalUnpaidCents => months.fold(0, (s, m) => s + m.unpaidCents);
  int get totalForecastCents => months.fold(0, (s, m) => s + m.forecastCents);
  int get totalNetCents => months.fold(0, (s, m) => s + m.netCents);
  int get totalCount => months.fold(0, (s, m) => s + m.count);

  bool get isEmpty => months.every((m) => m.isZero);

  int? get currentTotalPaidCents => currentMonths?.fold(0, (s, m) => s! + m.paidCents);
  int? get currentTotalUnpaidCents => currentMonths?.fold(0, (s, m) => s! + m.unpaidCents);
  int? get currentTotalForecastCents => currentMonths?.fold(0, (s, m) => s! + m.forecastCents);
  int? get currentTotalNetCents => currentMonths?.fold(0, (s, m) => s! + m.netCents);
  int? get currentTotalCount => currentMonths?.fold(0, (s, m) => s! + m.count);

  int? get deltaPaidCents => comparing ? currentTotalPaidCents! - totalPaidCents : null;
  int? get deltaUnpaidCents => comparing ? currentTotalUnpaidCents! - totalUnpaidCents : null;
  int? get deltaForecastCents => comparing ? currentTotalForecastCents! - totalForecastCents : null;
  int? get deltaNetCents => comparing ? currentTotalNetCents! - totalNetCents : null;
  int? get deltaCount => comparing ? currentTotalCount! - totalCount : null;
}
