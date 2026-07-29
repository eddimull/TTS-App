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
    return FinanceTrends.fromJson({
      'year': year,
      'available_years': [year],
      'unearned': 123456,
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
  testWidgets('renders Unearned card with as-of-today caption at 320pt',
      (tester) async {
    // User's phone is narrow (~320pt) — verify no overflow at that width.
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

    // The summary cards sit below the chart — scroll them into view.
    await tester.scrollUntilVisible(find.text('UNEARNED'), 200);
    expect(find.text('UNEARNED'), findsOneWidget);
    expect(find.text('\$1,234.56'), findsOneWidget);
    expect(find.text('as of today, all years'), findsOneWidget);
  });
}
