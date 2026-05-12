import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_term.dart';
import 'package:tts_bandmate/features/bookings/providers/contract_editor_provider.dart';

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
}
