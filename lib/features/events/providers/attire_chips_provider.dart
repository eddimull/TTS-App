import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/attire_chip_repository.dart';
import '../data/models/attire_chip.dart';

/// The six hardcoded dress-code labels shown when the band has no backend chips.
///
/// Public so that [_AttireField] in `event_edit_screen.dart` can use the same
/// list as a fallback during provider loading / error states, keeping the UI
/// consistent.
const kAttireDefaultLabels = [
  'All black',
  'All white',
  'Black tie',
  'Cocktail',
  'Smart casual',
  'Casual',
];

List<AttireChip> get _hardcodedDefaults => [
      for (var i = 0; i < kAttireDefaultLabels.length; i++)
        AttireChip(id: null, label: kAttireDefaultLabels[i], position: i),
    ];

// ── State ─────────────────────────────────────────────────────────────────────

/// Holds the chip list as loaded from the backend.
///
/// Use [displayChips] to get the correct chips to render — it substitutes the
/// hardcoded defaults when the backend list is empty.
class AttireChipsState {
  const AttireChipsState({required this.chips});

  /// Chips as returned by the backend, in position order.
  final List<AttireChip> chips;

  /// The chips to render in the UI.
  ///
  /// When [chips] is empty the band has no persisted chips yet — return the six
  /// hardcoded defaults so the form is immediately usable. Once the user saves
  /// their first chip the GET refresh will populate [chips] with the seeded
  /// defaults *and* the new chip, making them all deletable.
  List<AttireChip> get displayChips =>
      chips.isEmpty ? _hardcodedDefaults : chips;

  AttireChipsState copyWith({List<AttireChip>? chips}) =>
      AttireChipsState(chips: chips ?? this.chips);
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AttireChipsNotifier extends AsyncNotifier<AttireChipsState> {
  @override
  Future<AttireChipsState> build() async {
    // Await the selected band so we block until the AsyncNotifier has resolved.
    // Using .future causes build() to re-run whenever the band changes.
    final bandId = await ref.watch(selectedBandProvider.future);
    if (bandId == null) return const AttireChipsState(chips: []);

    final repo = ref.watch(attireChipRepositoryProvider);
    final chips = await repo.list(bandId);
    return AttireChipsState(chips: chips);
  }

  // ── Mutations ────────────────────────────────────────────────────────────────

  /// Adds [label] as a new chip, optimistically updating the list.
  ///
  /// On success, re-fetches the full list from the backend (the POST may have
  /// seeded the six defaults on the first call). On failure, rolls back to the
  /// previous state and rethrows so the caller can show an alert.
  Future<void> addChip(String label) async {
    final bandId = ref.read(selectedBandProvider).asData?.value;
    if (bandId == null) return;

    final previous = state;

    // Optimistic insert — use a sentinel id of -1 (never persisted).
    final optimistic = AttireChip(id: null, label: label, position: 9999);
    if (previous is AsyncData<AttireChipsState>) {
      final currentChips = previous.value.chips;
      state = AsyncData(
        previous.value.copyWith(chips: [...currentChips, optimistic]),
      );
    }

    try {
      final repo = ref.read(attireChipRepositoryProvider);
      await repo.create(bandId, label);
      // Refresh so we get the canonical list (defaults seeded + new chip).
      final refreshed = await repo.list(bandId);
      state = AsyncData(AttireChipsState(chips: refreshed));
    } catch (e, st) {
      // Roll back and surface the error while preserving the previous value.
      // copyWithPrevious is @internal but is the documented way to keep
      // state.value populated on the error side in Riverpod 3.x.
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<AttireChipsState>.error(e, st)
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(previous);
      rethrow;
    }
  }

  /// Removes the chip identified by [chipId], optimistically updating the list.
  ///
  /// On failure, rolls back and rethrows.
  Future<void> removeChip(int chipId) async {
    final bandId = ref.read(selectedBandProvider).asData?.value;
    if (bandId == null) return;

    final previous = state;

    if (previous is AsyncData<AttireChipsState>) {
      final remaining =
          previous.value.chips.where((c) => c.id != chipId).toList();
      state = AsyncData(previous.value.copyWith(chips: remaining));
    }

    try {
      final repo = ref.read(attireChipRepositoryProvider);
      await repo.delete(bandId, chipId);
    } catch (e, st) {
      // ignore: invalid_use_of_internal_member
      state = AsyncValue<AttireChipsState>.error(e, st)
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(previous);
      rethrow;
    }
  }
}

final attireChipsProvider =
    AsyncNotifierProvider<AttireChipsNotifier, AttireChipsState>(
  AttireChipsNotifier.new,
);
