import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_term.dart';
import 'package:tts_bandmate/features/bookings/widgets/contract/contract_terms_list.dart';

void main() {
  group('ContractTermsList', () {
    final terms = [
      const ContractTerm(id: 0, title: 'Alpha', content: 'A'),
      const ContractTerm(id: 1, title: 'Beta', content: 'B'),
    ];

    testWidgets('preview mode renders titles uppercased', (t) async {
      await t.pumpWidget(CupertinoApp(
        home: CupertinoPageScaffold(
          child: ContractTermsList(
            terms: terms,
            editMode: false,
            onTitleChanged: (_, __) {},
            onContentChanged: (_, __) {},
            onAddSection: () {},
            onRemoveSection: (_) {},
            onReorder: (_, __) {},
          ),
        ),
      ));
      expect(find.text('ALPHA'), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget);
    });

    testWidgets('edit mode shows add button', (t) async {
      await t.pumpWidget(CupertinoApp(
        home: CupertinoPageScaffold(
          child: ContractTermsList(
            terms: terms,
            editMode: true,
            onTitleChanged: (_, __) {},
            onContentChanged: (_, __) {},
            onAddSection: () {},
            onRemoveSection: (_) {},
            onReorder: (_, __) {},
          ),
        ),
      ));
      expect(find.text('Add Section'), findsOneWidget);
    });

    testWidgets('empty + edit shows placeholder', (t) async {
      await t.pumpWidget(CupertinoApp(
        home: CupertinoPageScaffold(
          child: ContractTermsList(
            terms: const [],
            editMode: true,
            onTitleChanged: (_, __) {},
            onContentChanged: (_, __) {},
            onAddSection: () {},
            onRemoveSection: (_) {},
            onReorder: (_, __) {},
          ),
        ),
      ));
      expect(
        find.textContaining('No terms yet'),
        findsOneWidget,
      );
    });
  });
}
