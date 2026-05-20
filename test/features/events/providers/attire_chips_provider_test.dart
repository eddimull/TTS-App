import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/attire_chip_repository.dart';
import 'package:tts_bandmate/features/events/data/models/attire_chip.dart';
import 'package:tts_bandmate/features/events/providers/attire_chips_provider.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';

// ignore_for_file: invalid_use_of_internal_member

// ── Fake repository ───────────────────────────────────────────────────────────

class FakeAttireChipRepository implements AttireChipRepository {
  FakeAttireChipRepository({
    List<AttireChip>? chips,
    AttireChip? createdChip,
    bool throwOnCreate = false,
    bool throwOnDelete = false,
  })  : _chips = List.of(chips ?? []),
        _createdChip = createdChip,
        _throwOnCreate = throwOnCreate,
        _throwOnDelete = throwOnDelete;

  final List<AttireChip> _chips;
  final AttireChip? _createdChip;
  final bool _throwOnCreate;
  final bool _throwOnDelete;

  int listCallCount = 0;
  int createCallCount = 0;
  int deleteCallCount = 0;

  // After the first create the backend "seeds" defaults — simulate that by
  // returning the preset list + the new chip on subsequent list() calls.
  List<AttireChip>? _seededChips;

  @override
  Future<List<AttireChip>> list(int bandId) async {
    listCallCount++;
    return List.of(_seededChips ?? _chips);
  }

  @override
  Future<AttireChip> create(int bandId, String label) async {
    createCallCount++;
    if (_throwOnCreate) throw Exception('network error');
    final chip = _createdChip ??
        AttireChip(id: 99, label: label, position: _chips.length);
    // Simulate backend seeding: once any chip is created, list returns chips.
    _seededChips = [..._chips, chip];
    return chip;
  }

  @override
  Future<void> delete(int bandId, int chipId) async {
    deleteCallCount++;
    if (_throwOnDelete) throw Exception('network error');
    _chips.removeWhere((c) => c.id == chipId);
    _seededChips = List.of(_chips);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer(
  FakeAttireChipRepository repo, {
  int? bandId = 1,
}) {
  return ProviderContainer(
    overrides: [
      attireChipRepositoryProvider.overrideWithValue(repo),
      // Directly seed the AsyncValue so the notifier sees a resolved band ID
      // without touching SecureStorage or re-running the real build().
      selectedBandProvider.overrideWith(
        () => _FakeSelectedBandNotifier(bandId: bandId),
      ),
    ],
  );
}

/// Subclasses [SelectedBandNotifier] to satisfy the typed [overrideWith]
/// constraint. Immediately resolves to [bandId] without touching storage.
class _FakeSelectedBandNotifier extends SelectedBandNotifier {
  _FakeSelectedBandNotifier({required this.bandId});
  final int? bandId;

  @override
  // ignore: must_call_super
  Future<int?> build() async => bandId;
}

const _chip1 = AttireChip(id: 1, label: 'All black', position: 0);
const _chip2 = AttireChip(id: 2, label: 'Casual', position: 1);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('attireChipsProvider', () {
    test('returns hardcoded defaults when API returns empty list', () async {
      final repo = FakeAttireChipRepository(chips: []);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final state =
          await container.read(attireChipsProvider.future);

      // Backend is empty — provider should expose six hardcoded defaults.
      expect(state.chips, isEmpty,
          reason: 'chips list should be empty (no backend data)');
      expect(state.displayChips, hasLength(kAttireDefaultLabels.length));
      expect(
        state.displayChips.map((c) => c.label).toList(),
        kAttireDefaultLabels,
      );
      // All defaults are placeholders (id == null).
      expect(state.displayChips.every((c) => c.isPlaceholder), isTrue);
    });

    test('returns API list when backend has chips; does not mix in defaults',
        () async {
      final repo = FakeAttireChipRepository(chips: [_chip1, _chip2]);
      final container = _makeContainer(repo);
      addTearDown(container.dispose);

      final state = await container.read(attireChipsProvider.future);

      expect(state.chips, hasLength(2));
      expect(state.displayChips, hasLength(2),
          reason: 'defaults must NOT be appended when API returns chips');
      expect(state.displayChips.map((c) => c.label).toList(),
          ['All black', 'Casual']);
      expect(state.displayChips.none((c) => c.isPlaceholder), isTrue);
    });

    group('addChip', () {
      test('optimistically inserts chip and confirms after successful POST',
          () async {
        final repo = FakeAttireChipRepository(chips: [_chip1]);
        final container = _makeContainer(repo);
        addTearDown(container.dispose);

        // Seed initial state.
        await container.read(attireChipsProvider.future);

        final notifier =
            container.read(attireChipsProvider.notifier);

        // Don't await — inspect optimistic state immediately after call begins.
        final addFuture = notifier.addChip('Formal');

        // The notifier may be in loading or data at this point; wait for settle.
        await addFuture;

        final state = container.read(attireChipsProvider);
        expect(state.hasError, isFalse);

        // After success, list is refreshed from backend (which now includes the
        // seeded chips from the fake).
        final chips = state.requireValue.chips;
        expect(chips.any((c) => c.label == 'Formal'), isTrue);
        expect(repo.createCallCount, 1);
        expect(repo.listCallCount, 2); // initial + post-create refresh
      });

      test('rolls back optimistic insert on network error', () async {
        final repo = FakeAttireChipRepository(
          chips: [_chip1],
          throwOnCreate: true,
        );
        final container = _makeContainer(repo);
        addTearDown(container.dispose);

        await container.read(attireChipsProvider.future);
        final notifier =
            container.read(attireChipsProvider.notifier);

        // addChip rethrows — catch it so the test doesn't fail on the throw.
        await expectLater(
          notifier.addChip('Formal'),
          throwsException,
        );

        final state = container.read(attireChipsProvider);
        // State should be in error but preserve the previous data.
        expect(state.hasError, isTrue);
        expect(state.value, isNotNull,
            reason: 'prior chips must be preserved on rollback');
        // Optimistic chip should be gone — only _chip1 remains.
        expect(
          state.value!.chips.none((c) => c.label == 'Formal'),
          isTrue,
        );
      });
    });

    group('removeChip', () {
      test('optimistically removes chip and confirms after successful DELETE',
          () async {
        final repo = FakeAttireChipRepository(chips: [_chip1, _chip2]);
        final container = _makeContainer(repo);
        addTearDown(container.dispose);

        await container.read(attireChipsProvider.future);
        final notifier =
            container.read(attireChipsProvider.notifier);

        await notifier.removeChip(_chip1.id!);

        final state = container.read(attireChipsProvider);
        expect(state.hasError, isFalse);
        expect(
          state.requireValue.chips.none((c) => c.id == _chip1.id),
          isTrue,
        );
        expect(repo.deleteCallCount, 1);
      });

      test('rolls back optimistic removal on network error', () async {
        final repo = FakeAttireChipRepository(
          chips: [_chip1, _chip2],
          throwOnDelete: true,
        );
        final container = _makeContainer(repo);
        addTearDown(container.dispose);

        await container.read(attireChipsProvider.future);
        final notifier =
            container.read(attireChipsProvider.notifier);

        await expectLater(
          notifier.removeChip(_chip1.id!),
          throwsException,
        );

        final state = container.read(attireChipsProvider);
        expect(state.hasError, isTrue);
        expect(state.value, isNotNull,
            reason: 'chips must be preserved on rollback');
        // _chip1 should be restored.
        expect(
          state.value!.chips.any((c) => c.id == _chip1.id),
          isTrue,
        );
      });
    });
  });
}

// Small helper to keep test assertions readable — mirrors the Dart 3 collection
// extension that isn't guaranteed in all SDK versions in this project.
extension<T> on Iterable<T> {
  bool none(bool Function(T) test) => !any(test);
}
