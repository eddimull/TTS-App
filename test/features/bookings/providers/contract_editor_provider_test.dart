import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_term.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';
import 'package:tts_bandmate/features/bookings/providers/contract_editor_provider.dart';

/// Stub repository whose [saveContractTerms] throws the configured error.
/// All other methods are unimplemented — the editor only touches save on
/// the error path under test.
class _ThrowingSaveRepo implements BookingsRepository {
  _ThrowingSaveRepo(this.thrownError);

  final Object thrownError;
  int saveCalls = 0;

  @override
  Future<BookingDetail> saveContractTerms(
    int bandId,
    int bookingId,
    List<ContractTerm> terms, {
    String? buyerNameOverride,
  }) async {
    saveCalls++;
    throw thrownError;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Captures the args passed to [saveContractTerms] and returns a detail.
class _CapturingSaveRepo implements BookingsRepository {
  String? lastBuyerNameOverride;
  int saveCalls = 0;

  @override
  Future<BookingDetail> saveContractTerms(
    int bandId,
    int bookingId,
    List<ContractTerm> terms, {
    String? buyerNameOverride,
  }) async {
    saveCalls++;
    lastBuyerNameOverride = buyerNameOverride;
    return _detailWithTerms(terms);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

BookingDetail _detailWithTerms(List<ContractTerm> terms) {
  return BookingDetail(
    id: 1,
    name: 'Test Booking',
    startDate: '2026-06-01',
    endDate: '2026-06-01',
    eventCount: 1,
    isMultiEvent: false,
    isPaid: false,
    contacts: const [],
    events: const [],
    contract: BookingContract(
      id: 1,
      customTerms: terms,
    ),
  );
}

BookingDetail _detailWithOverride(String? override) {
  return BookingDetail(
    id: 1,
    name: 'Test Booking',
    startDate: '2026-06-01',
    endDate: '2026-06-01',
    eventCount: 1,
    isMultiEvent: false,
    isPaid: false,
    contacts: const [],
    events: const [],
    contract: BookingContract(
      id: 1,
      customTerms: const [],
      buyerNameOverride: override,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContractEditorNotifier helpers', () {
    test('loadInitialTermsForTest reads bundled JSON asset', () async {
      // The asset is registered in pubspec.yaml under flutter.assets.
      final notifier = ContractEditorNotifier(
        (bandId: 1, bookingId: 1),
      );
      final loaded = await notifier.loadInitialTermsForTest();
      expect(loaded.length, greaterThanOrEqualTo(5));
      expect(loaded.first.title, isNotEmpty);
    });

    test('reorder swaps elements', () {
      final terms = [
        const ContractTerm(id: 0, title: 'A', content: ''),
        const ContractTerm(id: 1, title: 'B', content: ''),
        const ContractTerm(id: 2, title: 'C', content: ''),
      ];
      final reordered = ContractEditorNotifier.reorderForTest(terms, 0, 2);
      expect(reordered.map((t) => t.title).toList(), ['B', 'A', 'C']);
    });

    test(
      'reorder is a no-op when adjusted index equals original (ReorderableListView semantics)',
      () {
        final terms = [
          const ContractTerm(id: 0, title: 'A', content: ''),
          const ContractTerm(id: 1, title: 'B', content: ''),
        ];
        // Moving item 0 to index 1 in ReorderableListView semantics is a no-op
        // (the item is already at the position before the gap).
        final reordered = ContractEditorNotifier.reorderForTest(terms, 0, 1);
        expect(reordered.map((t) => t.title).toList(), ['A', 'B']);
      },
    );
  });

  group('ContractEditorNotifier save() error handling', () {
    test('save() failure preserves in-flight terms in state.value', () async {
      const key = (bandId: 1, bookingId: 1);
      // Seed customTerms so build() doesn't have to load the bundled asset.
      final seededTerms = [
        const ContractTerm(id: -1, title: 'Original', content: 'Body'),
      ];
      final repo = _ThrowingSaveRepo(Exception('network down'));

      final container = ProviderContainer(overrides: [
        bookingsRepositoryProvider.overrideWithValue(repo),
        bookingDetailProvider.overrideWith(
          (ref, args) async => _detailWithTerms(seededTerms),
        ),
      ]);
      addTearDown(container.dispose);

      // Drive the initial build to completion.
      await container.read(contractEditorProvider(key).future);

      final notifier = container.read(contractEditorProvider(key).notifier);
      // Stable id assigned by build() is 0 (first term).
      notifier.updateTitle(0, 'Edited');

      // Force-save to bypass the 500ms debounce; this should throw inside the
      // notifier but be caught and folded into the AsyncValue's error side.
      await notifier.save(force: true);

      expect(repo.saveCalls, 1);

      final s = container.read(contractEditorProvider(key));
      expect(s.hasError, isTrue, reason: 'failure should be surfaced');
      expect(
        s.value,
        isNotNull,
        reason: 'prior terms must NOT be clobbered on save failure',
      );
      expect(s.value!.terms, hasLength(1));
      expect(s.value!.terms.first.title, 'Edited');
    });
  });

  group('ContractEditorNotifier buyerNameOverride', () {
    test('seeds buyerNameOverride from the loaded contract', () async {
      const key = (bandId: 1, bookingId: 1);
      final repo = _CapturingSaveRepo();
      final container = ProviderContainer(overrides: [
        bookingsRepositoryProvider.overrideWithValue(repo),
        bookingDetailProvider.overrideWith(
          (ref, args) async => _detailWithOverride('The City of Scott'),
        ),
      ]);
      addTearDown(container.dispose);

      await container.read(contractEditorProvider(key).future);
      final s = container.read(contractEditorProvider(key));
      expect(s.value!.buyerNameOverride, 'The City of Scott');
    });

    test('updateBuyerNameOverride sets the value and save() sends it', () async {
      const key = (bandId: 1, bookingId: 1);
      final repo = _CapturingSaveRepo();
      final container = ProviderContainer(overrides: [
        bookingsRepositoryProvider.overrideWithValue(repo),
        bookingDetailProvider.overrideWith(
          (ref, args) async => _detailWithTerms(
            [const ContractTerm(id: -1, title: 'A', content: 'B')],
          ),
        ),
      ]);
      addTearDown(container.dispose);

      await container.read(contractEditorProvider(key).future);
      final notifier = container.read(contractEditorProvider(key).notifier);

      notifier.updateBuyerNameOverride('The City of Scott');
      await notifier.save(force: true);

      expect(repo.saveCalls, 1);
      expect(repo.lastBuyerNameOverride, 'The City of Scott');
      final s = container.read(contractEditorProvider(key));
      expect(s.value!.buyerNameOverride, 'The City of Scott');
    });
  });
}
