import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';

// ── Lodging ───────────────────────────────────────────────────────────────────

class LodgingLinksSection extends StatelessWidget {
  const LodgingLinksSection({super.key, required this.lodgings});
  final List<LodgingSummary> lodgings;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          for (int i = 0; i < lodgings.length; i++) ...[
            if (i > 0)
              Container(
                  height: 0.5,
                  color: CupertinoColors.separator.resolveFrom(context)),
            LodgingLinkRow(lodging: lodgings[i]),
          ],
        ],
      ),
    );
  }
}

class LodgingLinkRow extends StatelessWidget {
  const LodgingLinkRow({super.key, required this.lodging});
  final LodgingSummary lodging;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, MMM d');
    final checkIn = lodging.parsedCheckIn;
    final checkOut = DateTime.tryParse(lodging.checkOutAt) ?? checkIn;
    final range = '${dateFmt.format(checkIn)} – ${dateFmt.format(checkOut)}';

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => context.push('/lodging/${lodging.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(CupertinoIcons.bed_double,
                size: 18, color: context.secondaryText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lodging.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  Text(range,
                      style: TextStyle(
                          fontSize: 13, color: context.secondaryText)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right,
                size: 16, color: context.tertiaryText),
          ],
        ),
      ),
    );
  }
}
