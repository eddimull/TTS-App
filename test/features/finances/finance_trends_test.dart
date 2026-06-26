import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';

Map<String, dynamic> _month(int m, {int paid = 0, int unpaid = 0, int forecast = 0, int net = 0, int count = 0}) =>
    {'month': m, 'paid': paid, 'unpaid': unpaid, 'forecast': forecast, 'net': net, 'count': count};

void main() {
  group('FinanceTrends.fromJson', () {
    test('parses months, available_years, snapshot_date', () {
      final t = FinanceTrends.fromJson({
        'year': 2026,
        'snapshot_date': '2025-06-15',
        'available_years': [2026, 2025],
        'months': [_month(2, paid: 300000, unpaid: 120000, forecast: 420000, net: 84000, count: 2)],
      });
      expect(t.year, 2026);
      expect(t.snapshotDate, '2025-06-15');
      expect(t.availableYears, [2026, 2025]);
      expect(t.months.single.paidCents, 300000);
      expect(t.months.single.count, 2);
      expect(t.currentMonths, isNull);
    });

    test('parses current_months when present', () {
      final t = FinanceTrends.fromJson({
        'year': 2026, 'available_years': [2026], 'months': [_month(1)],
        'current_months': [_month(1, paid: 500000, count: 3)],
      });
      expect(t.currentMonths, isNotNull);
      expect(t.currentMonths!.single.paidCents, 500000);
    });
  });

  group('derived totals', () {
    final t = FinanceTrends.fromJson({
      'year': 2026, 'available_years': [2026],
      'months': [
        _month(1, paid: 100000, unpaid: 50000, forecast: 150000, net: 30000, count: 2),
        _month(2, paid: 200000, unpaid: 0, forecast: 200000, net: 40000, count: 1),
      ],
    });

    test('sums per-series totals', () {
      expect(t.totalPaidCents, 300000);
      expect(t.totalUnpaidCents, 50000);
      expect(t.totalForecastCents, 350000);
      expect(t.totalNetCents, 70000);
      expect(t.totalCount, 3);
    });

    test('isEmpty true only when every month is all-zero', () {
      final empty = FinanceTrends.fromJson({'year': 2026, 'available_years': [], 'months': [_month(1), _month(2)]});
      expect(empty.isEmpty, isTrue);
      expect(t.isEmpty, isFalse);
    });
  });

  group('compare deltas', () {
    final t = FinanceTrends.fromJson({
      'year': 2026, 'snapshot_date': '2025-06-15', 'available_years': [2026],
      'months': [_month(1, paid: 100000, count: 2)],
      'current_months': [_month(1, paid: 250000, count: 5)],
    });

    test('current totals sum current_months', () {
      expect(t.currentTotalPaidCents, 250000);
      expect(t.currentTotalCount, 5);
    });
    test('deltas are current minus snapshot', () {
      expect(t.deltaPaidCents, 150000);
      expect(t.deltaCount, 3);
    });
    test('deltas null when not comparing', () {
      final n = FinanceTrends.fromJson({'year': 2026, 'available_years': [2026], 'months': [_month(1, paid: 100000)]});
      expect(n.deltaPaidCents, isNull);
      expect(n.currentTotalPaidCents, isNull);
    });
  });
}
