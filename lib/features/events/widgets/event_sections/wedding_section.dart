import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';

// ── Wedding ───────────────────────────────────────────────────────────────────

class WeddingSection extends StatelessWidget {
  const WeddingSection({super.key, required this.wedding});
  final WeddingDetail wedding;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wedding.onsite != null) ...[
            Row(
              children: [
                Icon(
                  wedding.onsite!
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.xmark_circle_fill,
                  size: 16,
                  color: wedding.onsite!
                      ? CupertinoColors.systemGreen.resolveFrom(context)
                      : CupertinoColors.systemGrey.resolveFrom(context),
                ),
                const SizedBox(width: 8),
                Text(
                  wedding.onsite! ? 'Ceremony On-site' : 'Ceremony Off-site',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ],
          if (wedding.onsite != null && wedding.dances.isNotEmpty) ...[
            Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                color: CupertinoColors.separator.resolveFrom(context)),
          ],
          if (wedding.dances.isNotEmpty) ...[
            Text(
              'Special Dances',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.secondaryText),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < wedding.dances.length; i++) ...[
              if (i > 0)
                Container(
                    height: 0.5,
                    color: CupertinoColors.separator.resolveFrom(context)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        _formatDanceTitle(wedding.dances[i].title),
                        style: TextStyle(
                            fontSize: 13, color: context.secondaryText),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        wedding.dances[i].data?.isNotEmpty == true
                            ? wedding.dances[i].data!
                            : 'TBD',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatDanceTitle(String raw) =>
      raw.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
}
