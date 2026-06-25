import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/finances/payout_editor/config/guided_config_scaffold.dart';
import 'package:tts_bandmate/features/finances/payout_editor/config/node_config_form.dart';
import 'package:tts_bandmate/features/finances/payout_editor/providers/payout_flow_provider.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_role.dart';
import 'package:tts_bandmate/features/personnel/providers/roles_provider.dart';

/// Resolves immediately to an empty role list so the roster recipients step
/// doesn't spin on a real network call (which would leave a pending timer).
class _EmptyRolesNotifier extends RolesNotifier {
  _EmptyRolesNotifier() : super(0);
  @override
  Future<List<BandRole>> build() async => const <BandRole>[];
}

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

  group('NodeConfigForm (guided)', () {
    Future<void> pump(WidgetTester t, String type, Map<String, dynamic> data,
        {Map<String, dynamic>? preview}) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          // The roster recipients step watches the band's roles/members. Stub
          // them with resolved-empty data so no real network call (and no
          // never-ending CupertinoActivityIndicator timer) is started.
          // ignore: deprecated_member_use  // overrideWith2 isn't available for these family providers in this Riverpod version.
          rolesProvider.overrideWith(() => _EmptyRolesNotifier()),
          // ignore: deprecated_member_use
          payoutBandMembersProvider.overrideWith((ref, bandId) async => const []),
        ],
        child: CupertinoApp(
          home: NodeConfigForm(
            bandId: 1,
            nodeType: type,
            data: data,
            previewValues: preview,
            onChanged: () {},
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('payoutGroup renders 3 tabs', (t) async {
      await pump(t, 'payoutGroup', {'sourceType': 'roster'});
      expect(find.text('Recipients'), findsOneWidget);
      expect(find.text('Take'), findsOneWidget);
      expect(find.text('Split'), findsOneWidget);
    });

    testWidgets('income renders a single step (no Recipients/Split tabs)', (t) async {
      await pump(t, 'income', {'amount': 5000, 'label': 'Income'});
      expect(find.text('Recipients'), findsNothing);
      expect(find.text('Split'), findsNothing);
    });

    testWidgets('tapping an incoming-allocation card sets the data key', (t) async {
      final data = <String, dynamic>{'sourceType': 'roster', 'incomingAllocationType': 'remainder'};
      await pump(t, 'payoutGroup', data);
      await t.tap(find.text('Take'));
      await t.pump();
      await t.tap(find.text('Fixed amount'));
      await t.pump();
      expect(data['incomingAllocationType'], 'fixed');
    });

    testWidgets('tapping a distribution card sets distributionMode', (t) async {
      final data = <String, dynamic>{'sourceType': 'roster', 'distributionMode': 'equal_split'};
      await pump(t, 'payoutGroup', data);
      await t.tap(find.text('Split'));
      await t.pump();
      await t.tap(find.text('Fixed per member'));
      await t.pump();
      expect(data['distributionMode'], 'fixed');
    });

    testWidgets('fixed distribution shows the per-member amount field', (t) async {
      final data = <String, dynamic>{'sourceType': 'roster', 'distributionMode': 'fixed'};
      await pump(t, 'payoutGroup', data);
      await t.tap(find.text('Split'));
      await t.pump();
      expect(find.text('Fixed amount per member (\$)'), findsOneWidget);
    });

    testWidgets('tapping a bandCut type card sets cutType', (t) async {
      final data = <String, dynamic>{'cutType': 'percentage'};
      await pump(t, 'bandCut', data);
      await t.tap(find.text('Tiered'));
      await t.pump();
      expect(data['cutType'], 'tiered');
    });

    testWidgets('preview bar shows per-member figure from node_values', (t) async {
      await pump(t, 'payoutGroup', {'sourceType': 'roster', 'distributionMode': 'equal_split'},
          preview: {'perMember': 500, 'memberCount': 3});
      await t.tap(find.text('Split'));
      await t.pump();
      expect(find.textContaining(r'$500'), findsWidgets);
    });
  });
}
