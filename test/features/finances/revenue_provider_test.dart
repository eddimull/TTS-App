import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';

class _FakeFinancesRepository implements FinancesRepository {
  _FakeFinancesRepository(this._revenue);
  final BandRevenue _revenue;
  int fetchCount = 0;

  @override
  Future<BandRevenue> fetchRevenue(int bandId) async {
    fetchCount++;
    return _revenue;
  }

  @override
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) =>
      throw UnimplementedError();
  @override
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) =>
      throw UnimplementedError();
}

void main() {
  ProviderContainer containerWith(_FakeFinancesRepository repo) =>
      ProviderContainer(
        overrides: [financesRepositoryProvider.overrideWithValue(repo)],
      );

  test('revenueProvider loads revenue from the repository', () async {
    final fake = _FakeFinancesRepository(
      const BandRevenue(years: [RevenueYear(year: 2026, totalCents: 5000)]),
    );
    final container = containerWith(fake);
    addTearDown(container.dispose);

    final result = await container.read(revenueProvider(1).future);
    expect(result.years.single.totalCents, 5000);
    expect(fake.fetchCount, 1);
  });

  test('refresh re-fetches', () async {
    final fake = _FakeFinancesRepository(
      const BandRevenue(years: [RevenueYear(year: 2026, totalCents: 5000)]),
    );
    final container = containerWith(fake);
    addTearDown(container.dispose);

    await container.read(revenueProvider(1).future);
    await container.read(revenueProvider(1).notifier).refresh();
    expect(fake.fetchCount, 2);
  });
}
