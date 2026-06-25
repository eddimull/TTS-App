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
    final accent = CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
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
            Icon(spec.icon, size: 22, color: selected ? accent : CupertinoColors.secondaryLabel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: label)),
                  const SizedBox(height: 1),
                  Text(spec.description,
                      style: const TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel)),
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
          Text(label, style: const TextStyle(fontSize: 13, color: CupertinoColors.secondaryLabel)),
          Text(value ?? '—',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
        ],
      ),
    );
  }
}
