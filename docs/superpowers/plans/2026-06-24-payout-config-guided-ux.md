# Guided Payout-Config UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the raw `label: value` payout-node config form with a guided, plain-language config — tab chips, question headings, described option cards, and a pinned live-preview bar — consistent across all node types.

**Architecture:** A shared `GuidedConfigScaffold` (nav bar + tab chips + body + pinned preview bar) renders a list of `ConfigStep`s. Each node type builds its own step list; `payoutGroup` has 3 tabs (Recipients/Take/Split), simple types have 1. Primary enum choices become `OptionCard`s (icon + title + description + checkmark) instead of dropdowns. The form still edits `node.data` in place and calls `onChanged` — unchanged contract — and now also receives the node's `node_values` for the preview. Presentation-only; no saved-data or backend change.

**Tech Stack:** Flutter / Cupertino, Riverpod (existing `NodeConfigForm` is a `ConsumerStatefulWidget`), `flutter_test` WidgetTester.

---

## File Structure

- **Modify** `lib/features/finances/payout_editor/config/node_config_form.dart` — the form. Add `previewValues` param; replace the flat `ListView` build + `_fieldsForType()` with step-list builders rendered through `GuidedConfigScaffold`. Keep the existing helper widgets (`_TextField`, `_NumberField`, `_ToggleField`, `_FieldRow`) and `PayoutNodeOptions`. Remove `_SectionHeader` and `_EnumField` once nothing uses them.
- **Create** `lib/features/finances/payout_editor/config/guided_config_scaffold.dart` — `GuidedConfigScaffold`, `ConfigStep`, `OptionCard`, `OptionCardGroup`, `PreviewBar`, and the static option-description map. Pure presentation widgets, no Riverpod.
- **Modify** `lib/features/finances/payout_editor/screens/payout_flow_editor_screen.dart:275` — pass `previewValues: _nodeValues[node.id]` into `NodeConfigForm`.
- **Create** `test/features/finances/payout_config_form_test.dart` — widget tests.

---

## Task 1: Option-description data + OptionCard widgets

**Files:**
- Create: `lib/features/finances/payout_editor/config/guided_config_scaffold.dart`
- Test: `test/features/finances/payout_config_form_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/finances/payout_config_form_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: FAIL — `guided_config_scaffold.dart` / `OptionCardGroup` / `OptionSpec` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/finances/payout_editor/config/guided_config_scaffold.dart`:

```dart
// Guided config presentation widgets for the payout node config form:
// described option cards, the step scaffold (tab chips + body + pinned preview),
// and the option-description data. Pure presentation — no Riverpod, no data
// mutation; callers pass current values + onSelect/onChanged callbacks.

import 'package:flutter/cupertino.dart';

/// One selectable option: raw value + how to present it.
class OptionSpec {
  const OptionSpec(this.value, this.icon, this.title, this.description);
  final String value;
  final IconData icon;
  final String title;
  final String description;
}

/// A vertical group of tappable, described option cards (single-select).
class OptionCardGroup extends StatelessWidget {
  const OptionCardGroup({
    super.key,
    required this.selected,
    required this.options,
    required this.onSelect,
  });

  final String selected;
  final List<OptionSpec> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final o in options)
          _OptionCard(spec: o, selected: o.value == selected, onTap: () => onSelect(o.value)),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.spec, required this.selected, required this.onTap});
  final OptionSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoColors.activeBlue;
    final border = selected
        ? accent
        : CupertinoDynamicColor.resolve(CupertinoColors.systemGrey4, context);
    final fill = selected
        ? accent.withValues(alpha: 0.08)
        : CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(spec.icon, size: 22, color: selected ? accent : CupertinoColors.systemGrey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: label)),
                  const SizedBox(height: 1),
                  Text(spec.description,
                      style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                ],
              ),
            ),
            if (selected)
              const Icon(CupertinoIcons.checkmark_alt, size: 18, color: CupertinoColors.activeBlue),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/payout_editor/config/guided_config_scaffold.dart test/features/finances/payout_config_form_test.dart
git commit -m "feat(finances): OptionCard widgets for guided payout config"
```

---

## Task 2: PreviewBar widget

**Files:**
- Modify: `lib/features/finances/payout_editor/config/guided_config_scaffold.dart`
- Test: `test/features/finances/payout_config_form_test.dart`

- [ ] **Step 1: Write the failing test**

Append a new group to the test file:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: FAIL — `PreviewBar` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `guided_config_scaffold.dart`:

```dart
/// Pinned bottom bar showing a node's computed figure. A null [value] renders a
/// neutral placeholder rather than stale numbers.
class PreviewBar extends StatelessWidget {
  const PreviewBar({super.key, required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemBackground, context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(
            color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
          Text(value ?? '—',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/payout_editor/config/guided_config_scaffold.dart test/features/finances/payout_config_form_test.dart
git commit -m "feat(finances): PreviewBar for guided payout config"
```

---

## Task 3: GuidedConfigScaffold (tabs + body + pinned preview)

**Files:**
- Modify: `lib/features/finances/payout_editor/config/guided_config_scaffold.dart`
- Test: `test/features/finances/payout_config_form_test.dart`

- [ ] **Step 1: Write the failing test**

Append:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: FAIL — `ConfigStep` / `GuidedConfigScaffold` not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `guided_config_scaffold.dart`:

```dart
/// One step/tab of a guided config: a tab label, a question heading + subtitle,
/// and a builder for the step's body fields.
class ConfigStep {
  const ConfigStep({
    required this.tab,
    required this.question,
    required this.subtitle,
    required this.builder,
  });
  final String tab;
  final String question;
  final String subtitle;
  final WidgetBuilder builder;
}

/// The guided config shell: nav bar (title + optional trailing), tab chips when
/// there's more than one step, the active step's question + body (scrolling),
/// and a pinned preview bar at the bottom.
class GuidedConfigScaffold extends StatefulWidget {
  const GuidedConfigScaffold({
    super.key,
    required this.title,
    required this.steps,
    required this.preview,
    this.trailing,
  });

  final String title;
  final List<ConfigStep> steps;
  final Widget preview;
  final Widget? trailing;

  @override
  State<GuidedConfigScaffold> createState() => _GuidedConfigScaffoldState();
}

class _GuidedConfigScaffoldState extends State<GuidedConfigScaffold> {
  int _active = 0;

  @override
  Widget build(BuildContext context) {
    // Clamp in case the step list shrank (e.g. node type changed) between builds.
    final active = _active < widget.steps.length ? _active : 0;
    final step = widget.steps[active];
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.title),
        trailing: widget.trailing,
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (widget.steps.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.steps.length; i++)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _active = i),
                          child: Container(
                            margin: EdgeInsets.only(right: i == widget.steps.length - 1 ? 0 : 6),
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: i == active
                                  ? CupertinoColors.activeBlue
                                  : CupertinoDynamicColor.resolve(
                                      CupertinoColors.tertiarySystemFill, context),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.steps[i].tab,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: i == active
                                    ? CupertinoColors.white
                                    : CupertinoColors.label,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Text(step.question,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(step.subtitle,
                      style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                  const SizedBox(height: 14),
                  step.builder(context),
                ],
              ),
            ),
            widget.preview,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/payout_editor/config/guided_config_scaffold.dart test/features/finances/payout_config_form_test.dart
git commit -m "feat(finances): GuidedConfigScaffold tabbed shell"
```

---

## Task 4: Option specs (icons + descriptions) for each enum

**Files:**
- Modify: `lib/features/finances/payout_editor/config/guided_config_scaffold.dart`
- Test: `test/features/finances/payout_config_form_test.dart`

- [ ] **Step 1: Write the failing test**

Append:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: FAIL — `kSourceSpecs` etc. not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `guided_config_scaffold.dart`:

```dart
// Option specs: icon + plain-language description per enum value. Titles reuse
// PayoutNodeOptions.labelFor at the call site; these carry the icon + description.

const kSourceSpecs = <OptionSpec>[
  OptionSpec('roster', CupertinoIcons.person_2, 'Roster', "People on the band's roster"),
  OptionSpec('allMembers', CupertinoIcons.star, 'All members', 'Everyone in the band'),
  OptionSpec('specific', CupertinoIcons.person_crop_circle, 'Specific members', 'Pick individuals'),
  OptionSpec('roles', CupertinoIcons.square_list, 'Role slots', 'By role on the roster'),
  OptionSpec('paymentGroup', CupertinoIcons.group, 'Payment group', 'A saved payment group'),
];

const kIncomingSpecs = <OptionSpec>[
  OptionSpec('remainder', CupertinoIcons.equal, 'Remainder', 'Everything left after other groups'),
  OptionSpec('percentage', CupertinoIcons.percent, 'Percentage', 'A share of the incoming amount'),
  OptionSpec('fixed', CupertinoIcons.money_dollar, 'Fixed amount', 'A set dollar amount'),
];

const kDistributionSpecs = <OptionSpec>[
  OptionSpec('equal_split', CupertinoIcons.equal_circle, 'Equally', 'Everyone gets the same'),
  OptionSpec('percentage', CupertinoIcons.percent, 'By percentage', 'Custom share per person'),
  OptionSpec('fixed', CupertinoIcons.money_dollar, 'Fixed per member', 'Set dollar amount each'),
  OptionSpec('tiered', CupertinoIcons.chart_bar, 'Tiered', 'Different amounts by tier'),
  OptionSpec('weighted', CupertinoIcons.slider_horizontal_3, 'Weighted', 'Weighted shares per person'),
];

const kCutSpecs = <OptionSpec>[
  OptionSpec('percentage', CupertinoIcons.percent, 'Percentage', 'A percent of the income'),
  OptionSpec('fixed', CupertinoIcons.money_dollar, 'Fixed amount', 'A set dollar amount'),
  OptionSpec('tiered', CupertinoIcons.chart_bar, 'Tiered', 'Different cuts by tier'),
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/finances/payout_editor/config/guided_config_scaffold.dart test/features/finances/payout_config_form_test.dart
git commit -m "feat(finances): option specs (icons + descriptions) for payout enums"
```

---

## Task 5: Rewrite NodeConfigForm to use the guided scaffold

**Files:**
- Modify: `lib/features/finances/payout_editor/config/node_config_form.dart`
- Modify: `lib/features/finances/payout_editor/screens/payout_flow_editor_screen.dart:275`
- Test: `test/features/finances/payout_config_form_test.dart`

This task replaces the `build()`/`_fieldsForType()`/`_payoutGroupFields()` rendering with step-list builders, adds the `previewValues` param, and threads it from the host. The `_set`/`_setNested`/`PayoutNodeOptions` and the field/list helpers stay.

- [ ] **Step 1: Write the failing tests (data-key wiring + tabs + preview)**

Append (note the import of `node_config_form.dart`):

```dart
  group('NodeConfigForm (guided)', () {
    // Pump the form with the given node type/data and capture mutations.
    Future<void> pump(WidgetTester t, String type, Map<String, dynamic> data,
        {Map<String, dynamic>? preview}) async {
      await t.pumpWidget(ProviderScope(
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

    testWidgets('income renders a single step (no tab row)', (t) async {
      await pump(t, 'income', {'amount': 5000, 'label': 'Income'});
      // Single-step types show the question but not multiple tab chips.
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: FAIL — `NodeConfigForm` has no `previewValues` param; option-card text not found (still dropdowns).

- [ ] **Step 3: Add the `previewValues` param**

In `node_config_form.dart`, add the field + constructor param (after `onDelete`):

```dart
  final int bandId;
  final String nodeType;
  final Map<String, dynamic> data;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  /// This node's computed values from the preview API (input/output/allocated/
  /// perMember/memberCount/bandCut), or null when not yet available.
  final Map<String, dynamic>? previewValues;
```

```dart
  const NodeConfigForm({
    super.key,
    required this.bandId,
    required this.nodeType,
    required this.data,
    required this.onChanged,
    this.onDelete,
    this.previewValues,
  });
```

- [ ] **Step 4: Replace `build()` with the guided scaffold**

In `node_config_form.dart`, add the import at the top (after `node_list_fields.dart`):

```dart
import 'guided_config_scaffold.dart';
```

Replace the entire `build()` method (currently lines ~146-187) with:

```dart
  @override
  Widget build(BuildContext context) {
    final title = (widget.data['label'] as String?)?.trim().isNotEmpty == true
        ? widget.data['label'] as String
        : _friendlyType(widget.nodeType);
    return GuidedConfigScaffold(
      title: title,
      trailing: widget.onDelete == null
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                Navigator.pop(context);
                widget.onDelete!();
              },
              child: const Icon(CupertinoIcons.delete,
                  color: CupertinoColors.destructiveRed),
            ),
      preview: _previewBar(),
      steps: _stepsForType(),
    );
  }

  PreviewBar _previewBar() {
    final v = widget.previewValues;
    String money(dynamic n) {
      final d = (n as num?)?.toDouble() ?? 0;
      return '\$${d.toStringAsFixed(d.truncateToDouble() == d ? 0 : 2)}';
    }
    switch (widget.nodeType) {
      case 'payoutGroup':
        final mc = v?['memberCount'];
        return PreviewBar(
          label: 'Each member gets',
          value: v == null ? null : '${money(v['perMember'])}${mc != null ? ' · $mc people' : ''}',
        );
      case 'bandCut':
        return PreviewBar(label: 'To members', value: v == null ? null : money(v['output']));
      case 'income':
        return PreviewBar(label: 'Output', value: v == null ? null : money(v['output']));
      default:
        return PreviewBar(label: 'Input', value: v == null ? null : money(v['input']));
    }
  }
```

- [ ] **Step 5: Add the step builders (replacing `_fieldsForType`/`_payoutGroupFields`)**

In `node_config_form.dart`, delete `_fieldsForType()` (lines ~189-233) and `_payoutGroupFields()` (the whole method) and add:

```dart
  List<ConfigStep> _stepsForType() {
    switch (widget.nodeType) {
      case 'payoutGroup':
        return _payoutGroupSteps();
      case 'income':
        return [
          ConfigStep(
            tab: 'Income',
            question: 'How much income?',
            subtitle: 'The money entering this flow.',
            builder: (_) => Column(children: [
              _activeToggle(),
              _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
              _NumberField(label: 'Amount (\$)', value: _d['amount'], onChanged: (v) => _set('amount', v)),
            ]),
          ),
        ];
      case 'bandCut':
        return [
          ConfigStep(
            tab: 'The cut',
            question: "What's the band's cut?",
            subtitle: 'Taken before members are paid.',
            builder: (_) => Column(children: [
              _activeToggle(),
              _TextField(label: 'Label', value: '${_d['customLabel'] ?? ''}', onChanged: (v) => _set('customLabel', v)),
              OptionCardGroup(
                selected: '${_d['cutType'] ?? 'percentage'}',
                options: kCutSpecs,
                onSelect: (v) => _set('cutType', v),
              ),
              if (_d['cutType'] != 'tiered')
                _NumberField(label: 'Value', value: _d['value'], onChanged: (v) => _set('value', v)),
              if (_d['cutType'] == 'tiered')
                TierConfigField(data: _d, onChanged: widget.onChanged),
            ]),
          ),
        ];
      case 'conditional':
        final condType = '${_d['conditionType'] ?? 'bookingPrice'}';
        return [
          ConfigStep(
            tab: 'Condition',
            question: 'When does this apply?',
            subtitle: 'Routes to TRUE or FALSE based on the booking.',
            builder: (_) => Column(children: [
              _activeToggle(),
              _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
              _EnumRow(label: 'If', value: condType, options: PayoutNodeOptions.conditionTypes, onChanged: (v) {
                final ops = PayoutNodeOptions.operatorsFor(v);
                if (!ops.contains(_d['operator'])) _d['operator'] = ops.first;
                _set('conditionType', v);
              }),
              _EnumRow(
                label: 'Is',
                value: '${_d['operator'] ?? PayoutNodeOptions.operatorsFor(condType).first}',
                options: PayoutNodeOptions.operatorsFor(condType),
                onChanged: (v) => _set('operator', v),
              ),
              _valueFieldForCondition(condType),
            ]),
          ),
        ];
      default:
        return [
          ConfigStep(
            tab: 'Config',
            question: 'Settings',
            subtitle: '',
            builder: (_) => _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
          ),
        ];
    }
  }

  Widget _activeToggle() => _ToggleField(
        label: 'Node active',
        value: _d['deactivated'] != true,
        onChanged: (v) => _set('deactivated', !v),
      );

  List<ConfigStep> _payoutGroupSteps() {
    final sourceType = '${_d['sourceType'] ?? 'roster'}';
    final distMode = '${_d['distributionMode'] ?? 'equal_split'}';
    final incomingType = '${_d['incomingAllocationType'] ?? 'remainder'}';
    final allMembers = Map<String, dynamic>.from(_d['allMembersConfig'] as Map? ?? {});
    final roster = Map<String, dynamic>.from(_d['rosterConfig'] as Map? ?? {});

    return [
      ConfigStep(
        tab: 'Recipients',
        question: 'Who gets paid?',
        subtitle: "Choose where this group's people come from.",
        builder: (_) => Column(children: [
          _activeToggle(),
          _TextField(label: 'Label', value: '${_d['label'] ?? ''}', onChanged: (v) => _set('label', v)),
          OptionCardGroup(selected: sourceType, options: kSourceSpecs, onSelect: (v) => _set('sourceType', v)),
          if (sourceType == 'allMembers') ...[
            _ToggleField(label: 'Include owners', value: allMembers['includeOwners'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeOwners', v)),
            _ToggleField(label: 'Include members', value: allMembers['includeMembers'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeMembers', v)),
            _ToggleField(label: 'Include production', value: allMembers['includeProduction'] == true, onChanged: (v) => _setNested('allMembersConfig', 'includeProduction', v)),
            if (allMembers['includeProduction'] == true)
              _NumberField(label: 'Production count', value: allMembers['productionCount'], onChanged: (v) => _setNested('allMembersConfig', 'productionCount', v)),
          ],
          if (sourceType == 'roster') ...[
            _ToggleField(label: 'Weight by attendance', value: roster['useAttendanceWeighting'] != false, onChanged: (v) => _setNested('rosterConfig', 'useAttendanceWeighting', v)),
            _EnumRow(label: 'Member type', value: '${roster['memberTypeFilter'] ?? 'all'}', options: PayoutNodeOptions.memberTypeFilters, onChanged: (v) => _setNested('rosterConfig', 'memberTypeFilter', v)),
            _NumberField(label: 'Min events to qualify', value: roster['minEventsToQualify'], onChanged: (v) => _setNested('rosterConfig', 'minEventsToQualify', v)),
            _rosterRoleFilterField(),
          ],
          if (sourceType == 'paymentGroup')
            _NumberField(label: 'Payment group ID', value: _d['paymentGroupId'], onChanged: (v) => _set('paymentGroupId', v)),
          if (sourceType == 'specific') _specificMembersField(),
          if (sourceType == 'roles') _roleSlotsField(),
        ]),
      ),
      ConfigStep(
        tab: 'Take',
        question: 'How much does this group take?',
        subtitle: 'Out of the money flowing into this group.',
        builder: (_) => Column(children: [
          OptionCardGroup(selected: incomingType, options: kIncomingSpecs, onSelect: (v) => _set('incomingAllocationType', v)),
          if (incomingType != 'remainder')
            _NumberField(
              label: incomingType == 'percentage' ? 'Percent (%)' : 'Amount (\$)',
              value: _d['incomingAllocationValue'],
              onChanged: (v) => _set('incomingAllocationValue', v),
            ),
        ]),
      ),
      ConfigStep(
        tab: 'Split',
        question: 'How is it split?',
        subtitle: 'Among the people in this group.',
        builder: (_) => Column(children: [
          OptionCardGroup(selected: distMode, options: kDistributionSpecs, onSelect: (v) => _set('distributionMode', v)),
          if (distMode == 'fixed')
            _NumberField(label: 'Fixed amount per member (\$)', value: _d['fixedAmountPerMember'], onChanged: (v) => _set('fixedAmountPerMember', v)),
          if (distMode == 'percentage' || distMode == 'weighted')
            _memberAllocationsField(),
          if (distMode == 'tiered')
            TierConfigField(data: _d, onChanged: widget.onChanged),
          _ToggleField(label: 'Respect custom payouts', value: _d['respectCustomPayouts'] != false, onChanged: (v) => _set('respectCustomPayouts', v)),
          _NumberField(label: 'Minimum payout (\$)', value: _d['minimumPayout'], onChanged: (v) => _set('minimumPayout', v)),
        ]),
      ),
    ];
  }
```

- [ ] **Step 6: Replace `_EnumField` with `_EnumRow` and drop dead widgets**

The secondary dropdowns (member type, condition type/operator) still want a compact picker, not a full card. Rename the existing `_EnumField` class to `_EnumRow` (keeps its action-sheet picker). Then delete `_SectionHeader` (no longer used). In `node_config_form.dart`:

Rename the class declaration `class _EnumField extends StatelessWidget {` → `class _EnumRow extends StatelessWidget {` and its constructor `const _EnumField(` → `const _EnumRow(`. Delete the `_SectionHeader` class (lines ~369-378).

- [ ] **Step 7: Thread `previewValues` from the host**

In `payout_flow_editor_screen.dart`, update the `NodeConfigForm(...)` call (line ~275):

```dart
        builder: (_) => NodeConfigForm(
          bandId: widget.bandId,
          nodeType: node.type,
          data: node.data,
          previewValues: (_nodeValues[node.id] as Map?)?.cast<String, dynamic>(),
          onChanged: () => _repaintNode(node),
          onDelete: () => _confirmDeleteNode(node),
        ),
```

- [ ] **Step 8: Run the analyzer + tests**

Run: `flutter analyze lib/features/finances/payout_editor/`
Expected: No issues found.

Run: `flutter test test/features/finances/payout_config_form_test.dart`
Expected: PASS (all groups, ~14 tests).

- [ ] **Step 9: Run the adapter suite to confirm no regression**

Run: `flutter test test/features/finances/payout_flow_adapter_test.dart`
Expected: PASS (9 tests — no data-shape change).

- [ ] **Step 10: Commit**

```bash
git add lib/features/finances/payout_editor/config/node_config_form.dart lib/features/finances/payout_editor/screens/payout_flow_editor_screen.dart test/features/finances/payout_config_form_test.dart
git commit -m "feat(finances): guided plain-language payout node config"
```

---

## Task 6: On-device verification + polish

**Files:** (verification only — no required edits)

- [ ] **Step 1: Re-add the temp dev cert bypass for device login**

In `lib/main.dart`, re-add the `kDebugMode` `_DevHttpOverrides` block (do NOT commit it). It is stripped before every commit.

- [ ] **Step 2: Build to the device and walk every node type**

Run: `flutter run -d R5CR60PRF6Y`

Verify on device:
- payoutGroup shows 3 tabs; tapping each swaps the question; option cards have icon + description; selecting one updates the node + preview bar.
- Fixed distribution shows the per-member amount field; tiered shows the tier editor; percentage/weighted show the allocations list.
- income / bandCut / conditional each show a single guided step in the same style.
- The preview bar shows real figures from the backend; neutral `—` when amount is 0.
- Save → reopen round-trips unchanged; web canvas unaffected.

- [ ] **Step 3: Strip the cert bypass and confirm clean**

Run: `git checkout -- lib/main.dart` (or remove the block)
Run: `git diff lib/main.dart` → expect empty.

- [ ] **Step 4: Final analyze + full payout test run**

Run: `flutter analyze lib/features/finances/`
Expected: No issues found.

Run: `flutter test test/features/finances/`
Expected: PASS (adapter + config form suites).

- [ ] **Step 5: Push to the fix branch + open/refresh the PR**

(The current branch is `fix/payout-fixed-amount-input` off main, already on PR #43. This UX work can extend it or go on its own branch — confirm with the user before pushing.)

```bash
git push origin HEAD
```

---

## Notes for the implementer

- **`PayoutNodeOptions.labelFor`** still resolves friendly labels for the `_EnumRow` secondary pickers and any raw-value display. The OptionSpec titles are independent (slightly more conversational, e.g. "Fixed per member" vs "Fixed amount").
- **The nested-list editors** (`TierConfigField`, `MemberAllocationsField` via `_memberAllocationsField()`, `RoleSlotsField` via `_roleSlotsField()`, `SpecificMembersField` via `_specificMembersField()`, `RosterRoleFilterField` via `_rosterRoleFilterField()`) are unchanged — they're just placed inside the relevant step's `builder`. Confirm those private helper methods still exist on the state class; they were defined alongside the old `_payoutGroupFields()` and must be kept.
- **Don't change any `data` keys.** This is presentation-only. The adapter/merge tests prove the data contract; they must stay green.
- **`previewValues` is read-only** in the form — it never writes back. It only feeds the preview bar.
- **Worked-example hints** (the spec's "$1,500 ÷ 3 = $500 each" inline notes) are
  optional polish for the Take/Split step builders. If `previewValues` is present,
  a small grey hint line can be added under the OptionCardGroup using the same
  `money()` helper (e.g. Split: "`${money(input)} ÷ $memberCount = ${money(perMember)} each`").
  Keep them out of the widget tests (they depend on preview data) — assert only the
  preview bar for computed-value coverage. Skip the hints if they crowd the layout
  on a small phone; the preview bar is the primary feedback and is required.
