// Guided config presentation widgets for the payout node config form:
// described option cards, the step scaffold (tab chips + body + pinned preview),
// and the option-description data. Pure presentation — no Riverpod, no data
// mutation; callers pass current values + onSelect/onChanged callbacks.

import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Muted secondary text (card descriptions, subtitles, preview label).
/// CupertinoColors.secondaryLabel is too dim on pure-black dark backgrounds, so
/// this uses a brighter grey in dark mode while staying subdued in light mode.
/// Resolve against context before use: `CupertinoDynamicColor.resolve(kSubtleText, context)`.
const kSubtleText = CupertinoDynamicColor.withBrightness(
  color: Color(0xFF6D6D72), // light mode — standard iOS secondary grey
  darkColor: Color(0xFFAEAEB2), // dark mode — brighter for legibility on black
);

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
    final accent = CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
    final border = selected
        ? accent
        : CupertinoDynamicColor.resolve(CupertinoColors.systemGrey4, context);
    final fill = selected
        ? accent.withValues(alpha: 0.08)
        : CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);
    final label = context.primaryText;
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
            Icon(spec.icon,
                size: 22,
                color: selected ? accent : CupertinoDynamicColor.resolve(kSubtleText, context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: label)),
                  const SizedBox(height: 1),
                  Text(spec.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(kSubtleText, context))),
                ],
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.checkmark_alt, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

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
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: CupertinoDynamicColor.resolve(kSubtleText, context))),
          Text(value ?? '—',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
        ],
      ),
    );
  }
}

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
                                    : context.primaryText,
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
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoDynamicColor.resolve(kSubtleText, context))),
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
