import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/config/guided_config_scaffold.dart';

void main() {
  Widget host(Widget child) =>
      CupertinoApp(home: CupertinoPageScaffold(child: child));

  group('OptionCardGroup', () {
    testWidgets('renders a card per option with title + description', (t) async {
      await t.pumpWidget(host(OptionCardGroup(
        selected: 'roster',
        options: const [
          OptionSpec('roster', CupertinoIcons.person_2, 'Roster',
              "People on the band's roster"),
          OptionSpec('allMembers', CupertinoIcons.star, 'All members',
              'Everyone in the band'),
        ],
        onSelect: (_) {},
      )));
      expect(find.text('Roster'), findsOneWidget);
      expect(find.text("People on the band's roster"), findsOneWidget);
      expect(find.text('All members'), findsOneWidget);
    });

    testWidgets('tapping a card calls onSelect with its value', (t) async {
      String? picked;
      await t.pumpWidget(host(OptionCardGroup(
        selected: 'roster',
        options: const [
          OptionSpec('roster', CupertinoIcons.person_2, 'Roster', 'desc'),
          OptionSpec('allMembers', CupertinoIcons.star, 'All members', 'desc'),
        ],
        onSelect: (v) => picked = v,
      )));
      await t.tap(find.text('All members'));
      expect(picked, 'allMembers');
    });
  });
}
