import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/band_settings_repository.dart';
import '../data/models/band_detail.dart';
import '../data/models/band_invitation.dart';
import '../data/models/band_member.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class BandSettingsState {
  const BandSettingsState({
    required this.detail,
    required this.members,
    required this.invitations,
  });

  final BandDetail detail;
  final List<BandMember> members;
  final List<BandInvitation> invitations;

  BandSettingsState copyWith({
    BandDetail? detail,
    List<BandMember>? members,
    List<BandInvitation>? invitations,
  }) {
    return BandSettingsState(
      detail: detail ?? this.detail,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
    );
  }
}

// ── Repository provider ───────────────────────────────────────────────────────

final bandSettingsRepositoryProvider =
    Provider<BandSettingsRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return BandSettingsRepository(dio);
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class BandSettingsNotifier extends AsyncNotifier<BandSettingsState> {
  BandSettingsNotifier(this._bandId);

  final int _bandId;

  BandSettingsRepository get _repo =>
      ref.read(bandSettingsRepositoryProvider);

  @override
  Future<BandSettingsState> build() async {
    final results = await Future.wait([
      _repo.getBandDetail(_bandId),
      _repo.getMembers(_bandId),
      _repo.getInvitations(_bandId),
    ]);
    return BandSettingsState(
      detail: results[0] as BandDetail,
      members: results[1] as List<BandMember>,
      invitations: results[2] as List<BandInvitation>,
    );
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }

  /// Optimistic toggle: flips locally, reverts and rethrows on failure.
  Future<void> togglePermission({
    required int memberId,
    required String permission,
    required bool granted,
  }) async {
    final current = state.value;
    if (current == null) return;

    // Apply optimistic update
    final updated = current.members.map((m) {
      if (m.id != memberId) return m;
      return m.withPermission(permission, granted: granted);
    }).toList();
    state = AsyncValue.data(current.copyWith(members: updated));

    try {
      await _repo.setPermission(_bandId, memberId,
          permission: permission, granted: granted);
    } catch (e) {
      // Revert
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> removeMember({required int userId}) async {
    await _repo.removeMember(_bandId, userId);
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        members: current.members.where((m) => m.id != userId).toList(),
      ),
    );
  }

  Future<void> revokeInvitation({required int invitationId}) async {
    await _repo.revokeInvitation(_bandId, invitationId);
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        invitations:
            current.invitations.where((i) => i.id != invitationId).toList(),
      ),
    );
  }

  Future<void> updateDetail(BandDetail detail) async {
    await _repo.updateBandDetail(
      detail.id,
      name: detail.name,
      siteName: detail.siteName,
      address: detail.address,
      city: detail.city,
      state: detail.state,
      zip: detail.zip,
    );
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(detail: detail));
  }
}

final bandSettingsProvider = AsyncNotifierProvider.family<
    BandSettingsNotifier, BandSettingsState, int>(
  (arg) => BandSettingsNotifier(arg),
);
