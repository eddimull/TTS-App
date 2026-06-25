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

  group('PreviewBar', () {
    testWidgets('shows label + formatted value', (t) async {
      await t.pumpWidget(host(const PreviewBar(label: 'Each member gets', value: r'$500')));
      expect(find.text('Each member gets'), findsOneWidget);
      expect(find.text(r'$500'), findsOneWidget);
    });

    testWidgets('shows placeholder when value is null', (t) async {
      await t.pumpWidget(host(const PreviewBar(label: 'Each member gets', value: null)));
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('GuidedConfigScaffold', () {
    List<ConfigStep> steps() => [
          ConfigStep(
            tab: 'Recipients',
            question: 'Who gets paid?',
            subtitle: 'Choose the source.',
            builder: (_) => const Text('STEP-RECIPIENTS'),
          ),
          ConfigStep(
            tab: 'Take',
            question: 'How much?',
            subtitle: 'Of the incoming amount.',
            builder: (_) => const Text('STEP-TAKE'),
          ),
        ];

    testWidgets('renders a chip per step and shows the first step body', (t) async {
      await t.pumpWidget(CupertinoApp(home: GuidedConfigScaffold(
        title: 'Payout Group',
        steps: steps(),
        preview: const PreviewBar(label: 'pays', value: '3 people'),
      )));
      expect(find.text('Recipients'), findsOneWidget);
      expect(find.text('Take'), findsOneWidget);
      expect(find.text('Who gets paid?'), findsOneWidget);
      expect(find.text('STEP-RECIPIENTS'), findsOneWidget);
      expect(find.text('STEP-TAKE'), findsNothing);
    });

    testWidgets('tapping a tab switches the visible step', (t) async {
      await t.pumpWidget(CupertinoApp(home: GuidedConfigScaffold(
        title: 'Payout Group',
        steps: steps(),
        preview: const PreviewBar(label: 'pays', value: '3 people'),
      )));
      await t.tap(find.text('Take'));
      await t.pump();
      expect(find.text('STEP-TAKE'), findsOneWidget);
      expect(find.text('How much?'), findsOneWidget);
      expect(find.text('STEP-RECIPIENTS'), findsNothing);
    });
  });

  group('option specs', () {
    test('every payout enum value has a spec', () {
      for (final v in ['roster', 'allMembers', 'specific', 'roles', 'paymentGroup']) {
        expect(kSourceSpecs.any((s) => s.value == v), isTrue, reason: 'source $v');
      }
      for (final v in ['remainder', 'percentage', 'fixed']) {
        expect(kIncomingSpecs.any((s) => s.value == v), isTrue, reason: 'incoming $v');
      }
      for (final v in ['equal_split', 'percentage', 'fixed', 'tiered', 'weighted']) {
        expect(kDistributionSpecs.any((s) => s.value == v), isTrue, reason: 'dist $v');
      }
      for (final v in ['percentage', 'fixed', 'tiered']) {
        expect(kCutSpecs.any((s) => s.value == v), isTrue, reason: 'cut $v');
      }
    });
  });
}
