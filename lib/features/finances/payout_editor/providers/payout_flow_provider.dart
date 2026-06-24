import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/payout_flow_repository.dart';

/// Lists a band's payout configs (summaries). Mirrors the finances provider
/// pattern: AsyncNotifier with the param passed via constructor.
class _PayoutConfigsNotifier extends AsyncNotifier<List<PayoutConfigSummary>> {
  _PayoutConfigsNotifier(this._bandId);
  final int _bandId;

  @override
  Future<List<PayoutConfigSummary>> build() {
    return ref.watch(payoutFlowRepositoryProvider).listConfigs(_bandId);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(payoutFlowRepositoryProvider).listConfigs(_bandId),
    );
  }
}

final payoutConfigsProvider = AsyncNotifierProvider.family<
    _PayoutConfigsNotifier, List<PayoutConfigSummary>, int>(
  (arg) => _PayoutConfigsNotifier(arg),
);

/// Identifies a single config to load (band + config id).
class PayoutConfigRef {
  const PayoutConfigRef({required this.bandId, required this.configId});
  final int bandId;
  final int configId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PayoutConfigRef &&
          bandId == other.bandId &&
          configId == other.configId;

  @override
  int get hashCode => Object.hash(bandId, configId);
}

/// Loads one config (with flow_diagram) for the editor.
final payoutConfigProvider =
    FutureProvider.family<PayoutConfigDetail, PayoutConfigRef>((ref, r) {
  return ref.watch(payoutFlowRepositoryProvider).getConfig(r.bandId, r.configId);
});
