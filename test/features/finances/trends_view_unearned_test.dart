import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';
import 'package:tts_bandmate/features/finances/screens/widgets/trends_view.dart';

class _FakeRepo implements FinancesRepository {
  @override
  Future<FinanceTrends> fetchTrends(int bandId,
      {required int year,
      String? snapshotDate,
      bool compareWithCurrent = false}) async {
    final thisYear = DateTime.now().year;
    return FinanceTrends.fromJson({
      'year': year,
      'available_years': [year],
      'unearned': 123456,
      'unearned_by_year': [
        {'year': thisYear, 'amount': 50000},
        {'year': thisYear + 1, 'amount': 73456},
      ],
      'months': [
        {
          'month': 1,
          'paid': 100000,
          'unpaid': 0,
          'forecast': 100000,
          'net': 20000,
          'count': 1,
        }
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
  Future<void> pumpTrends(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          financesRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: const CupertinoApp(
          home: CustomScrollView(slivers: [TrendsView(bandId: 1)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('UNEARNED'), 200);
  }

  testWidgets('Unearned card is year-scoped with tap affordance at 320pt',
      (tester) async {
    await pumpTrends(tester);

    expect(find.text('UNEARNED'), findsOneWidget);
    // Selected year defaults to the current year → that year's bucket only.
    expect(find.text('\$500.00'), findsOneWidget);
    expect(find.text('tap for all years'), findsOneWidget);
    // The all-years total is NOT on the card.
    expect(find.text('\$1,234.56'), findsNothing);
  });

  testWidgets('tapping the Unearned card opens the per-year breakdown sheet',
      (tester) async {
    await pumpTrends(tester);

    await tester.tap(find.text('UNEARNED'));
    await tester.pumpAndSettle();

    final thisYear = DateTime.now().year;
    expect(find.text('Unearned deposits'), findsOneWidget);
    expect(find.text('$thisYear'), findsWidgets); // year row (year picker may also show it)
    expect(find.text('${thisYear + 1}'), findsOneWidget);
    expect(find.text('\$500.00'), findsWidgets); // card + sheet row
    expect(find.text('\$734.56'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('\$1,234.56'), findsOneWidget);
  });
}
