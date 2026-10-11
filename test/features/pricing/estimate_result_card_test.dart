import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/pricing/data/models/price_estimate.dart';
import 'package:tts_bandmate/features/pricing/widgets/estimate_result_card.dart';

Widget _wrap(Widget child) => CupertinoApp(
      home: CupertinoPageScaffold(
        child: SafeArea(child: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  final estimate = PriceEstimate.fromJson({
    'estimate': 11250.0,
    'low': 9800.0,
    'high': 12600.0,
    'confidence': 'high',
    'baseline_source': 'history',
    'sample_size': 42,
    'breakdown': [
      {'key': 'baseline', 'label': 'Wedding baseline', 'type': 'base', 'amount': 9400.0},
      {'key': 'season', 'label': 'May (peak season)', 'type': 'multiplier', 'factor': 1.1, 'amount': 940.0},
      {'key': 'dow', 'label': 'Sunday', 'type': 'multiplier', 'factor': 0.9, 'amount': -200.0},
    ],
    'warnings': [
      {'code': 'date_conflict', 'message': 'You already have a booking on May 15, 2027.'}
    ],
    'comparables': [
      {'booking_id': 1, 'name': 'Smith Wedding', 'date': '2026-05-09', 'price': 9800.0, 'venue_name': 'Hall'}
    ],
  });

  testWidgets('renders estimate, range, confidence, breakdown, warnings, comparables',
      (tester) async {
    await tester.pumpWidget(_wrap(EstimateResultCard(estimate: estimate)));
    expect(find.text(r'$11,250'), findsOneWidget);
    expect(find.textContaining(r'$9,800 – $12,600'), findsOneWidget);
    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('Based on 42 past bookings'), findsOneWidget);
    expect(find.textContaining('May (peak season)'), findsOneWidget);
    expect(find.text(r'+$940'), findsOneWidget);
    expect(find.text(r'−$200'), findsOneWidget);
    expect(find.textContaining('already have a booking'), findsOneWidget);
    expect(find.text('Smith Wedding'), findsOneWidget);
    // No action without a callback.
    expect(find.text('Use this price'), findsNothing);
  });

  testWidgets('Use this price fires callback', (tester) async {
    var used = false;
    await tester.pumpWidget(_wrap(EstimateResultCard(
      estimate: estimate,
      onUsePrice: () => used = true,
    )));
    await tester.tap(find.text('Use this price'));
    expect(used, isTrue);
  });

  testWidgets('null estimate shows no-baseline message and no use button',
      (tester) async {
    await tester.pumpWidget(_wrap(EstimateResultCard(
      estimate: PriceEstimate.fromJson({
        'estimate': null,
        'warnings': [
          {'code': 'no_baseline', 'message': 'No booking history yet.'}
        ],
      }),
      onUsePrice: () {},
    )));
    expect(find.textContaining('Not enough booking history'), findsOneWidget);
    expect(find.text('No booking history yet.'), findsOneWidget);
    expect(find.text('Use this price'), findsNothing);
  });
}
