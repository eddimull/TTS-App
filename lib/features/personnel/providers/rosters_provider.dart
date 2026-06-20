import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'roles_provider.dart'; // re-exports personnelRepositoryProvider
import '../data/models/roster.dart';
import '../data/personnel_repository.dart';

// ── Roster list notifier ──────────────────────────────────────────────────────

class RostersNotifier extends AsyncNotifier<List<Roster>> {
  RostersNotifier(this._bandId);

  final int _bandId;

  PersonnelRepository get _repo => ref.read(personnelRepositoryProvider);

  @override
  Future<List<Roster>> build() => _repo.getRosters(_bandId);

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repo.getRosters(_bandId));
  }

  Future<void> createRoster(String name, {String? description}) async {
    final created = await _repo.createRoster(
      _bandId,
      name: name,
      description: description,
    );
    final current = state.value ?? [];
    state = AsyncValue.data([...current, created]);
  }

  Future<void> updateRoster(
    int rosterId, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    final updated = await _repo.updateRoster(
      _bandId,
      rosterId,
      name: name,
      description: description,
      isActive: isActive,
    );
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((r) => r.id == rosterId ? updated : r).toList(),
    );
  }

  Future<void> deleteRoster(int rosterId) async {
    await _repo.deleteRoster(_bandId, rosterId);
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((r) => r.id != rosterId).toList());
  }

  Future<void> setDefault(int rosterId) async {
    await _repo.setDefaultRoster(_bandId, rosterId);
    // Mark the new default; clear the old one.
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((r) => r.copyWith(isDefault: r.id == rosterId)).toList(),
    );
  }
}

final rostersProvider = AsyncNotifierProvider.family<
    RostersNotifier, List<Roster>, int>(
  (arg) => RostersNotifier(arg),
);

// ── Roster detail (FutureProvider.family) ─────────────────────────────────────

/// Keyed by (bandId, rosterId). Includes slots + full member list from the
/// detail endpoint. Screens that need full CRUD on a single roster use this.
final rosterDetailProvider =
    FutureProvider.family<Roster, ({int bandId, int rosterId})>(
  (ref, args) async {
    final repo = ref.watch(personnelRepositoryProvider);
    return repo.getRoster(args.bandId, args.rosterId);
  },
);
