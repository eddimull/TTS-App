import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/band_sub.dart';
import '../data/models/call_list_entry.dart';
import '../data/personnel_repository.dart';
import 'roles_provider.dart';

// ── Band subs ─────────────────────────────────────────────────────────────────

class BandSubsNotifier extends AsyncNotifier<List<BandSub>> {
  BandSubsNotifier(this._bandId);

  final int _bandId;

  PersonnelRepository get _repo => ref.read(personnelRepositoryProvider);

  @override
  Future<List<BandSub>> build() => _repo.getBandSubs(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getBandSubs(_bandId));
  }

  Future<void> invite({
    required String email,
    String? name,
    String? phone,
    int? bandRoleId,
    String? notes,
  }) async {
    await _repo.inviteBandSub(
      _bandId,
      email: email,
      name: name,
      phone: phone,
      bandRoleId: bandRoleId,
      notes: notes,
    );
    // Re-fetch so the unified active/pending list reflects the new invite
    // (an existing-user invite may surface as active, not pending).
    await refresh();
  }

  Future<void> remove(BandSub sub) async {
    if (sub.isInvitation) {
      await _repo.revokeBandSubInvitation(_bandId, sub.id);
    } else if (sub.userId != null) {
      await _repo.removeBandSub(_bandId, sub.userId!);
    }
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.where((s) => !(s.id == sub.id && s.type == sub.type)).toList(),
    );
  }
}

final bandSubsProvider =
    AsyncNotifierProvider.family<BandSubsNotifier, List<BandSub>, int>(
  (arg) => BandSubsNotifier(arg),
);

// ── Call lists ────────────────────────────────────────────────────────────────

class CallListsNotifier extends AsyncNotifier<List<CallListGroup>> {
  CallListsNotifier(this._bandId);

  final int _bandId;

  PersonnelRepository get _repo => ref.read(personnelRepositoryProvider);

  @override
  Future<List<CallListGroup>> build() => _repo.getCallLists(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getCallLists(_bandId));
  }

  Future<void> addCustom({
    required String name,
    required String email,
    required String phone,
    String? instrument,
    int? bandRoleId,
    bool sendInvite = true,
  }) async {
    await _repo.addCallListEntry(
      _bandId,
      instrument: instrument,
      bandRoleId: bandRoleId,
      customName: name,
      customEmail: email,
      customPhone: phone,
      sendInvite: sendInvite,
    );
    await refresh();
  }

  Future<void> deleteEntry(int entryId) async {
    await _repo.deleteCallListEntry(_bandId, entryId);
    await refresh();
  }
}

final callListsProvider =
    AsyncNotifierProvider.family<CallListsNotifier, List<CallListGroup>, int>(
  (arg) => CallListsNotifier(arg),
);
