import 'package:intl/intl.dart';

/// One year's total recorded revenue. [totalCents] is in cents (matches the
/// API payload, which mirrors the web's amount-in-cents storage).
class RevenueYear {
  const RevenueYear({required this.year, required this.totalCents});

  final int year;
  final int totalCents;

  factory RevenueYear.fromJson(Map<String, dynamic> json) {
    return RevenueYear(
      year: (json['year'] as num).toInt(),
      totalCents: (json['total'] as num).toInt(),
    );
  }

  /// Revenue in dollars (cents / 100).
  double get totalDollars => totalCents / 100.0;
}

/// A band's revenue broken down by year, newest first.
class BandRevenue {
  const BandRevenue({required this.years});

  /// Ordered newest year first (as returned by the API).
  final List<RevenueYear> years;

  factory BandRevenue.fromJson(Map<String, dynamic> json) {
    final raw = (json['revenue'] as List<dynamic>? ?? const []);
    return BandRevenue(
      years: raw
          .cast<Map<String, dynamic>>()
          .map(RevenueYear.fromJson)
          .toList(),
    );
  }

  /// All-time revenue in cents.
  int get totalCents => years.fold(0, (s, y) => s + y.totalCents);

  /// All-time revenue in dollars.
  double get totalDollars => totalCents / 100.0;

  /// Number of years with recorded revenue.
  int get yearsActive => years.length;

  /// Revenue for the current calendar year in cents, or null if no row exists.
  int? get currentYearCents {
    final now = DateTime.now().year;
    for (final y in years) {
      if (y.year == now) return y.totalCents;
    }
    return null;
  }

  /// Year-over-year change for the year at [index] (list is newest→oldest),
  /// as a signed percentage versus the next-older year. Returns null for the
  /// oldest row or when the previous year's total is zero.
  double? yearOverYearChange(int index) {
    if (index < 0 || index >= years.length - 1) return null;
    final current = years[index].totalCents;
    final previous = years[index + 1].totalCents;
    if (previous == 0) return null;
    return (current - previous) / previous * 100.0;
  }

  static final _currency = NumberFormat.currency(symbol: '\$');

  /// Formats a cents value as currency, e.g. 200000 -> "$2,000.00".
  static String formatCents(int cents) => _currency.format(cents / 100.0);
}
