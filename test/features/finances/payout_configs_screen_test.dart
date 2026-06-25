import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/data/payout_flow_repository.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart';
import 'package:tts_bandmate/features/finances/payout_editor/screens/payout_configs_screen.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

class _FakeRepo implements PayoutFlowRepository {
  @override
  Future<List<PayoutConfigSummary>> listConfigs(int bandId) async => const [];
  @override
  Future<List<PayoutTemplate>> listTemplates(int bandId) async =>
      const [PayoutTemplate(key: 'blank', name: 'Blank', description: 'Start fresh.')];
  @override
  Future<PayoutConfigDetail> createConfig(int b, String n, String t) async =>
      PayoutConfigDetail(id: 1, name: n, isActive: false, flowDiagram: const {'nodes': [], 'edges': []});
  @override
  Future<void> setActive(int b, int c) async {}
  @override
  Future<void> deleteConfig(int b, int c) async {}
  @override
  Future<PayoutConfigDetail> getConfig(int b, int c) => throw UnimplementedError();
  @override
  Future<PayoutConfigDetail> updateFlow(int b, int c, Map<String, dynamic> f, {bool? isActive}) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> preview(int b, Map<String, dynamic> f, num a) => throw UnimplementedError();
}

// Stub band notifier that immediately resolves to band 1.
class _StubBandNotifier extends SelectedBandNotifier {
  @override
  Future<int?> build() async => 1;
}

Widget _app({required bool owner}) => ProviderScope(
      overrides: [
        payoutFlowRepositoryProvider.overrideWithValue(_FakeRepo()),
        selectedBandProvider.overrideWith(_StubBandNotifier.new),
        isSelectedBandOwnerProvider.overrideWithValue(owner),
      ],
      child: const CupertinoApp(home: PayoutConfigsScreen()),
    );

void main() {
  testWidgets('owner sees the add button', (t) async {
    await t.pumpWidget(_app(owner: true));
    await t.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.add), findsOneWidget);
  });

  testWidgets('non-owner does not see the add button', (t) async {
    await t.pumpWidget(_app(owner: false));
    await t.pumpAndSettle();
    expect(find.byIcon(CupertinoIcons.add), findsNothing);
  });
}
