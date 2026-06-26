import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';

void main() {
  group('BandRevenue.fromJson', () {
    test('parses revenue rows', () {
      final r = BandRevenue.fromJson({
        'revenue': [
          {'year': 2026, 'total': 200000},
          {'year': 2025, 'total': 98000},
        ],
      });
      expect(r.years.length, 2);
      expect(r.years.first.year, 2026);
      expect(r.years.first.totalCents, 200000);
    });

    test('handles empty list', () {
      final r = BandRevenue.fromJson({'revenue': []});
      expect(r.years, isEmpty);
      expect(r.totalCents, 0);
      expect(r.yearsActive, 0);
      expect(r.currentYearCents, isNull);
    });
  });

  group('derived getters', () {
    final r = BandRevenue(years: const [
      RevenueYear(year: 2026, totalCents: 200000),
      RevenueYear(year: 2025, totalCents: 98000),
    ]);

    test('totalCents sums all years', () => expect(r.totalCents, 298000));
    test('yearsActive counts rows', () => expect(r.yearsActive, 2));
    test('currentYearCents finds current year', () {
      final cur = BandRevenue(years: [
        RevenueYear(year: DateTime.now().year, totalCents: 12345),
      ]);
      expect(cur.currentYearCents, 12345);
    });
    test('currentYearCents null when absent', () {
      final r2 = BandRevenue(years: const [RevenueYear(year: 2000, totalCents: 100)]);
      expect(r2.currentYearCents, isNull);
    });
  });

  group('yearOverYearChange', () {
    final r = BandRevenue(years: const [
      RevenueYear(year: 2026, totalCents: 12000), // +20% over 2025
      RevenueYear(year: 2025, totalCents: 10000), // -50% under 2024
      RevenueYear(year: 2024, totalCents: 20000), // oldest -> null
    ]);

    test('positive change', () => expect(r.yearOverYearChange(0), closeTo(20.0, 0.001)));
    test('negative change', () => expect(r.yearOverYearChange(1), closeTo(-50.0, 0.001)));
    test('oldest row returns null', () => expect(r.yearOverYearChange(2), isNull));

    test('previous total zero returns null (avoid div-by-zero)', () {
      final z = BandRevenue(years: const [
        RevenueYear(year: 2026, totalCents: 5000),
        RevenueYear(year: 2025, totalCents: 0),
      ]);
      expect(z.yearOverYearChange(0), isNull);
    });
  });
}
