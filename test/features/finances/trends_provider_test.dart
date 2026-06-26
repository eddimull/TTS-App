import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';
import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';

class _FakeRepo implements FinancesRepository {
  int calls = 0;
  int? lastYear;
  String? lastSnapshot;
  bool? lastCompare;

  @override
  Future<FinanceTrends> fetchTrends(int bandId,
      {required int year,
      String? snapshotDate,
      bool compareWithCurrent = false}) async {
    calls++;
    lastYear = year;
    lastSnapshot = snapshotDate;
    lastCompare = compareWithCurrent;
    return FinanceTrends.fromJson({
      'year': year,
      'available_years': [year],
      'months': [
        {'month': 1, 'paid': 1000, 'unpaid': 0, 'forecast': 1000, 'net': 200, 'count': 1}
      ],
    });
  }

  @override
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) =>
      throw UnimplementedError();
  @override
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) =>
      throw UnimplementedError();
  @override
  Future<BandRevenue> fetchRevenue(int bandId) => throw UnimplementedError();
}

void main() {
  ProviderContainer containerWith(_FakeRepo repo) => ProviderContainer(
        overrides: [financesRepositoryProvider.overrideWithValue(repo)],
      );

  test('TrendsParams value-equality', () {
    const a = TrendsParams(
        bandId: 1, year: 2026, snapshotDate: null, compareWithCurrent: false);
    const b = TrendsParams(
        bandId: 1, year: 2026, snapshotDate: null, compareWithCurrent: false);
    const c = TrendsParams(
        bandId: 1,
        year: 2026,
        snapshotDate: '2025-06-15',
        compareWithCurrent: false);
    expect(a, b);
    expect(a == c, isFalse);
  });

  test('trendsProvider forwards params and loads', () async {
    final fake = _FakeRepo();
    final container = containerWith(fake);
    addTearDown(container.dispose);

    const params = TrendsParams(
        bandId: 7,
        year: 2025,
        snapshotDate: '2024-12-31',
        compareWithCurrent: true);
    final result = await container.read(trendsProvider(params).future);

    expect(result.year, 2025);
    expect(fake.lastYear, 2025);
    expect(fake.lastSnapshot, '2024-12-31');
    expect(fake.lastCompare, isTrue);
  });

  test('refresh re-fetches', () async {
    final fake = _FakeRepo();
    final container = containerWith(fake);
    addTearDown(container.dispose);

    const params = TrendsParams(
        bandId: 1, year: 2026, snapshotDate: null, compareWithCurrent: false);
    await container.read(trendsProvider(params).future);
    await container.read(trendsProvider(params).notifier).refresh();
    expect(fake.calls, 2);
  });
}
