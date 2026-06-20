import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/models/band_role.dart';
import '../data/personnel_repository.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final personnelRepositoryProvider = Provider<PersonnelRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return PersonnelRepository(dio);
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class RolesNotifier extends AsyncNotifier<List<BandRole>> {
  RolesNotifier(this._bandId);

  final int _bandId;

  PersonnelRepository get _repo => ref.read(personnelRepositoryProvider);

  @override
  Future<List<BandRole>> build() => _repo.getRoles(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getRoles(_bandId));
  }

  Future<void> createRole(String name) async {
    final created = await _repo.createRole(_bandId, name: name);
    final current = state.value ?? [];
    state = AsyncValue.data([...current, created]);
  }

  Future<void> updateRole(int roleId, {String? name, bool? isActive}) async {
    final updated = await _repo.updateRole(
      _bandId,
      roleId,
      name: name,
      isActive: isActive,
    );
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((r) => r.id == roleId ? updated : r).toList(),
    );
  }

  Future<void> deleteRole(int roleId) async {
    await _repo.deleteRole(_bandId, roleId);
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((r) => r.id != roleId).toList());
  }

  Future<void> reorderRoles(List<BandRole> reordered) async {
    // Apply locally first (optimistic), remembering the prior order so we can
    // revert if the server rejects the change.
    final previous = state.value;
    state = AsyncValue.data(reordered);
    try {
      await _repo.reorderRoles(
        _bandId,
        reordered
            .asMap()
            .entries
            .map((e) => (id: e.value.id, displayOrder: e.key + 1))
            .toList(),
      );
    } catch (_) {
      if (previous != null) state = AsyncValue.data(previous);
      rethrow;
    }
  }
}

final rolesProvider = AsyncNotifierProvider.family<
    RolesNotifier, List<BandRole>, int>(
  (arg) => RolesNotifier(arg),
);
