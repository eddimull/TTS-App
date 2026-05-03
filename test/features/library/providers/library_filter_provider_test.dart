import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/providers/library_filter_provider.dart';

void main() {
  group('LibraryFilterState', () {
    test('default state is not active', () {
      const state = LibraryFilterState();
      expect(state.isActive, false);
      expect(state.activeCount, 0);
      expect(state.hiddenBandIds, isEmpty);
    });

    test('isActive flips when bands are hidden', () {
      const state = LibraryFilterState(hiddenBandIds: {7});
      expect(state.isActive, true);
      expect(state.activeCount, 1);
    });

    test('value-equality on identical hidden sets', () {
      const a = LibraryFilterState(hiddenBandIds: {1, 2});
      const b = LibraryFilterState(hiddenBandIds: {1, 2});
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different hidden sets are not equal', () {
      const a = LibraryFilterState(hiddenBandIds: {1});
      const b = LibraryFilterState(hiddenBandIds: {2});
      expect(a, isNot(equals(b)));
    });
  });

  group('LibraryFilterNotifier', () {
    test('toggleBand adds and removes a band id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(libraryFilterProvider.notifier);

      notifier.toggleBand(5);
      expect(container.read(libraryFilterProvider).hiddenBandIds, {5});

      notifier.toggleBand(5);
      expect(container.read(libraryFilterProvider).hiddenBandIds, isEmpty);
    });

    test('clear resets state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(libraryFilterProvider.notifier);
      notifier.toggleBand(1);
      notifier.toggleBand(2);
      expect(container.read(libraryFilterProvider).isActive, true);

      notifier.clear();
      expect(container.read(libraryFilterProvider).isActive, false);
      expect(container.read(libraryFilterProvider).hiddenBandIds, isEmpty);
    });
  });
}
