import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_member.dart';
import 'package:tts_bandmate/features/band_settings/providers/band_settings_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

import '../data/payout_flow_repository.dart';

/// Band members for the specific-members picker (reuses the band-settings repo).
final payoutBandMembersProvider =
    FutureProvider.family<List<BandMember>, int>((ref, bandId) {
  return ref.watch(bandSettingsRepositoryProvider).getMembers(bandId);
});

/// Whether the current user owns the selected band — gates editing/saving
/// (the backend PATCH endpoint is owner-only).
final isSelectedBandOwnerProvider = Provider<bool>((ref) {
  final bandId = ref.watch(selectedBandProvider).value;
  final auth = ref.watch(authProvider).value;
  if (bandId == null || auth is! AuthAuthenticated) return false;
  for (final b in auth.bands) {
    if (b.id == bandId) return b.isOwner;
  }
  return false;
});

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

  /// Creates a config from [template] and refreshes the list. Returns the
  /// created detail so the caller can open the editor for it.
  Future<PayoutConfigDetail> createConfig(String name, String template) async {
    final detail = await ref
        .read(payoutFlowRepositoryProvider)
        .createConfig(_bandId, name, template);
    await refresh();
    return detail;
  }

  /// Marks [configId] active (backend deactivates others) and refreshes.
  Future<void> setActive(int configId) async {
    await ref.read(payoutFlowRepositoryProvider).setActive(_bandId, configId);
    await refresh();
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
