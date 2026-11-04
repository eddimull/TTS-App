import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/features/finances/data/finances_repository.dart';
import 'package:tts_bandmate/features/finances/data/models/band_revenue.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_booking.dart';
import 'package:tts_bandmate/features/finances/data/models/finance_trends.dart';
import 'package:tts_bandmate/features/finances/data/models/payments_due.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart';
import 'package:tts_bandmate/features/finances/providers/finances_provider.dart';
import 'package:tts_bandmate/features/finances/screens/finances_screen.dart';
import 'package:tts_bandmate/features/finances/screens/widgets/payments_due_view.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

Map<String, dynamic> _row({
  String name = 'Hartley Wedding',
  String type = 'deposit',
  String status = 'overdue',
  String amount = '2500.00',
  String due = '2026-10-12',
  String event = '2027-03-06',
  int? daysLate = 23,
  String? since = '2026-10-12',
  String depositType = 'percent',
  String depositValue = '50.00',
  String depositAmount = '2500.00',
  String paid = '0.00',
}) =>
    {
      'booking_id': 7,
      'band_id': 1,
      'booking_name': name,
      'type': type,
      'status': status,
      'amount': amount,
      'due_date': due,
      'event_date': event,
      'days_late': daysLate,
      'overdue_since': since,
      'deposit_type': depositType,
      'deposit_value': depositValue,
      'deposit_amount': depositAmount,
      'amount_paid': paid,
    };

PaymentsDue _due({
  List<Map<String, dynamic>> overdue = const [],
  List<Map<String, dynamic>> next30 = const [],
  List<Map<String, dynamic>> later = const [],
  List<Map<String, dynamic>> older = const [],
}) {
  Map<String, dynamic> summary(List<Map<String, dynamic>> rows) => {
        'count': rows.length,
        'total': rows
            .fold<double>(0, (s, r) => s + double.parse(r['amount'] as String))
            .toStringAsFixed(2),
      };
  return PaymentsDue.fromJson({
    'summary': {
      'overdue': summary(overdue),
      'next_30': summary(next30),
      'later': summary(later),
      'older': summary(older),
    },
    'groups': {'overdue': overdue, 'next_30': next30, 'later': later, 'older': older},
  });
}

class _FakeRepo implements FinancesRepository {
  _FakeRepo(this.due);
  final PaymentsDue due;

  @override
  Future<PaymentsDue> fetchDue(int bandId) async => due;
  @override
  Future<List<FinanceBooking>> fetchUnpaid(int bandId, {int? year}) async => const [];
  @override
  Future<List<FinanceBooking>> fetchPaid(int bandId, {int? year}) async => const [];
  @override
  Future<BandRevenue> fetchRevenue(int bandId) => throw UnimplementedError();
  @override
  Future<FinanceTrends> fetchTrends(int bandId,
          {required int year, String? snapshotDate, bool compareWithCurrent = false}) =>
      throw UnimplementedError();
}

class _StubBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

Future<void> _pumpView(WidgetTester tester, PaymentsDue due, {List<String>? pushed}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => CustomScrollView(
        slivers: [PaymentsDueView(bandId: 1)],
      ),
    ),
    GoRoute(
      path: '/bookings/:band/:id/payments',
      builder: (_, state) {
        pushed?.add(state.uri.path);
        return const SizedBox();
      },
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [financesRepositoryProvider.overrideWithValue(_FakeRepo(due))],
    child: CupertinoApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final today = DateTime(2026, 11, 4);

  testWidgets('overdue rows say how late; totals show in the tile and section', (tester) async {
    await withClock(Clock.fixed(today), () async {
      await _pumpView(
        tester,
        _due(overdue: [
          _row(),
          _row(
            name: 'Cypress Club',
            type: 'balance',
            amount: '1800.00',
            due: '2026-10-17',
            event: '2026-10-24',
            daysLate: 11,
            since: '2026-10-24',
          ),
        ]),
      );

      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text(r'$4,300'), findsNWidgets(2));
      expect(find.text('2 payments'), findsOneWidget);
      expect(find.text('Deposit (50%) · was due Oct 12'), findsOneWidget);
      expect(find.text('23 days late'), findsOneWidget);
      expect(find.text('Balance · show was Oct 24'), findsOneWidget);
      expect(find.text('11 days late'), findsOneWidget);
    });
  });

  testWidgets('a balance in its last 7 days reads Due now, not late', (tester) async {
    await withClock(Clock.fixed(today), () async {
      await _pumpView(
        tester,
        _due(next30: [
          _row(
            name: 'Bayou Brewfest',
            type: 'balance',
            status: 'due_now',
            amount: '1800.00',
            due: '2026-10-30',
            event: '2026-11-06',
            daysLate: null,
            since: null,
          ),
        ]),
      );

      expect(find.text('Balance · show is Nov 6'), findsOneWidget);
      expect(find.text('Due now'), findsOneWidget);
      expect(find.textContaining('late'), findsNothing);
      expect(find.text('All caught up'), findsOneWidget);
    });
  });

  testWidgets('part-paid and flat deposits explain themselves', (tester) async {
    await withClock(Clock.fixed(today), () async {
      await _pumpView(
        tester,
        _due(next30: [
          _row(
            name: 'Parish Gala',
            status: 'upcoming',
            amount: '1250.00',
            due: '2026-11-09',
            daysLate: null,
            since: null,
            depositAmount: '3000.00',
            paid: '1750.00',
          ),
          _row(
            name: 'Flat One',
            status: 'upcoming',
            amount: '300.00',
            due: '2026-11-20',
            daysLate: null,
            since: null,
            depositType: 'amount',
            depositValue: '300.00',
            depositAmount: '300.00',
          ),
        ]),
      );

      expect(find.text(r'Deposit (50%) · $1,750 of $3,000 paid'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
    });
  });

  testWidgets('Later and Older stay collapsed until opened', (tester) async {
    await withClock(Clock.fixed(today), () async {
      await _pumpView(
        tester,
        _due(
          later: [_row(name: 'Later Show', type: 'balance', status: 'upcoming', due: '2027-01-09', daysLate: null, since: null)],
          older: [_row(name: 'Old Show', event: '2026-01-01')],
        ),
      );

      expect(find.text('Next: Jan 9, 2027'), findsOneWidget);
      expect(find.text('Shows over 90 days ago'), findsOneWidget);
      expect(find.text('Later Show'), findsNothing);
      expect(find.text('Old Show'), findsNothing);

      await tester.tap(find.text('Next: Jan 9, 2027'));
      await tester.pumpAndSettle();
      expect(find.text('Later Show'), findsOneWidget);

      await tester.tap(find.text('Shows over 90 days ago'));
      await tester.pumpAndSettle();
      expect(find.text('Old Show'), findsOneWidget);
    });
  });

  testWidgets('tapping a payment opens that booking\'s payments', (tester) async {
    final pushed = <String>[];
    await withClock(Clock.fixed(today), () async {
      await _pumpView(tester, _due(overdue: [_row()]), pushed: pushed);

      await tester.tap(find.text('Hartley Wedding'));
      await tester.pumpAndSettle();
    });

    expect(pushed, ['/bookings/1/7/payments']);
  });

  testWidgets('says so when nothing is due', (tester) async {
    await _pumpView(tester, _due());

    expect(find.text('No payments due. Every contracted booking is paid in full.'), findsOneWidget);
  });

  group('tabs by role', () {
    Future<void> pumpScreen(WidgetTester tester, {required bool owner}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          financesRepositoryProvider.overrideWithValue(_FakeRepo(_due(overdue: [_row()]))),
          selectedBandProvider.overrideWith(_StubBand.new),
          isSelectedBandOwnerProvider.overrideWithValue(owner),
        ],
        child: const CupertinoApp(home: FinancesScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('owners open on Due', (tester) async {
      await pumpScreen(tester, owner: true);

      expect(find.text('Due'), findsOneWidget);
      expect(find.text('OVERDUE'), findsOneWidget);
    });

    testWidgets('everyone else keeps today\'s tabs and opens on Unpaid', (tester) async {
      await pumpScreen(tester, owner: false);

      expect(find.text('Due'), findsNothing);
      expect(find.text('Unpaid'), findsOneWidget);
      expect(find.text('OVERDUE'), findsNothing);
    });
  });

  group('selectedBandOverdueCountProvider', () {
    ProviderContainer container({required bool owner}) {
      final c = ProviderContainer(overrides: [
        financesRepositoryProvider.overrideWithValue(_FakeRepo(_due(overdue: [_row()], older: [_row()]))),
        selectedBandProvider.overrideWith(_StubBand.new),
        isSelectedBandOwnerProvider.overrideWithValue(owner),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('counts overdue, not Older, for owners', () async {
      final c = container(owner: true);
      c.listen(selectedBandOverdueCountProvider, (_, __) {});
      await c.read(selectedBandProvider.future);
      await c.read(paymentsDueProvider(1).future);

      expect(c.read(selectedBandOverdueCountProvider), 1);
    });

    test('is zero for non-owners', () async {
      final c = container(owner: false);
      await c.read(selectedBandProvider.future);

      expect(c.read(selectedBandOverdueCountProvider), 0);
    });
  });
}
