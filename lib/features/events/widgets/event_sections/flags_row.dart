import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';

// ── Flags row ─────────────────────────────────────────────────────────────────

class FlagsRow extends StatelessWidget {
  const FlagsRow({super.key, required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (event.isPublic != null) {
      chips.add(FlagChip(
        label: event.isPublic! ? 'Public' : 'Private',
        icon: event.isPublic! ? CupertinoIcons.globe : CupertinoIcons.lock,
        active: event.isPublic!,
      ));
    }
    if (event.outside != null) {
      chips.add(FlagChip(
        label: 'Outdoor',
        icon: CupertinoIcons.sun_max,
        active: event.outside!,
      ));
    }
    if (event.backlineProvided != null) {
      chips.add(FlagChip(
        label: 'Backline',
        icon: CupertinoIcons.music_note_2,
        active: event.backlineProvided!,
      ));
    }
    if (event.productionNeeded != null) {
      chips.add(FlagChip(
        label: 'Production',
        icon: CupertinoIcons.bolt,
        active: event.productionNeeded!,
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }
}

class FlagChip extends StatelessWidget {
  const FlagChip(
      {super.key,
      required this.label, required this.icon, required this.active});
  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? CupertinoColors.systemBlue.resolveFrom(context)
        : CupertinoColors.systemGrey.resolveFrom(context);
    final bg = active
        ? CupertinoColors.systemBlue
            .resolveFrom(context)
            .withValues(alpha: 0.12)
        : CupertinoColors.systemGrey5.resolveFrom(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
