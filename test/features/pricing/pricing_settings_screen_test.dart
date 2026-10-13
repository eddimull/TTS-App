import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/pricing/data/models/pricing_settings.dart';
import 'package:tts_bandmate/features/pricing/data/pricing_repository.dart';
import 'package:tts_bandmate/features/pricing/providers/pricing_provider.dart';
import 'package:tts_bandmate/features/pricing/screens/pricing_settings_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeBand extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

class _FakeRepo extends PricingRepository {
  _FakeRepo() : super(Dio());
  @override
  Future<PricingSettingsBundle> getSettings(int bandId) async =>
      PricingSettingsBundle.fromJson({
        'settings': {
          'season_multipliers': {'5': 1.1},
          'add_ons': [
            {'key': 'p', 'label': 'Production', 'amount': 1500}
          ],
        },
        'event_types': [
          {'id': 1, 'name': 'Wedding'}
        ],
        'history': [
          {'event_type_id': 1, 'sample_size': 42, 'baseline': 9400.0}
        ],
      });
}

void main() {
  testWidgets('shows learned baseline, percent multipliers and add-ons',
      (tester) async {
    tester.view.physicalSize = const Size(640, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedBandProvider.overrideWith(_FakeBand.new),
        pricingRepositoryProvider.overrideWithValue(_FakeRepo()),
      ],
      child: const CupertinoApp(home: PricingSettingsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Wedding'), findsOneWidget);
    expect(find.textContaining(r'Learned $9,400 · 42 bookings'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // May = +10%
    expect(find.text('Save'), findsOneWidget);
  });
}
