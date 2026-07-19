import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';
import 'package:tts_bandmate/features/finances/screens/finances_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeFinancesRepo implements FinancesRepository {
  @override
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) async =>
      const [];

  @override
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) async =>
      const [];

  @override
  Future<BandRevenue> fetchRevenue(int bandId) =>
      throw UnimplementedError();

  @override
  Future<FinanceTrends> fetchTrends(
    int bandId, {
    required int year,
    String? snapshotDate,
    bool compareWithCurrent = false,
  }) =>
      throw UnimplementedError();
}

class _StubBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

Widget _app() => ProviderScope(
      overrides: [
        financesRepositoryProvider.overrideWithValue(_FakeFinancesRepo()),
        selectedBandProvider.overrideWith(_StubBandNotifier.new),
      ],
      child: const CupertinoApp(home: FinancesScreen()),
    );

void main() {
  testWidgets('tab labels stay on one line on narrow screens', (t) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(_app());
    await t.pumpAndSettle();

    final paidHeight = t.getSize(find.text('Paid')).height;
    for (final label in ['Unpaid', 'Revenue', 'Trends']) {
      expect(
        t.getSize(find.text(label)).height,
        paidHeight,
        reason: '"$label" should render on a single line like "Paid", '
            'not wrap on narrow screens',
      );
    }
  });
}
