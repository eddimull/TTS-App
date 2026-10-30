import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';

// ── Roster summary row ─────────────────────────────────────────────────────

/// One-line roster summary replacing the old inline grouped section (Task 5).
/// Tapping it pushes the full [RosterSheet] with the grouped list + controls.
class RosterSummaryRow extends StatelessWidget {
  const RosterSummaryRow({super.key, required this.event, required this.onTap});

  final EventDetail event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final members = event.members;
    final total = members.length;
    final subCount = members.where((m) => m.isSub).length;
    final pendingCount = members.where((m) {
      final status = m.attendanceStatus?.toLowerCase();
      return !m.isFilled ||
          status == null ||
          status.isEmpty ||
          status == 'pending';
    }).length;

    final countLabel =
        subCount > 0 ? '$total + $subCount sub' : '$total members';

    return SectionCard(
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Row(
          children: [
            Icon(CupertinoIcons.person_2,
                size: 18, color: context.secondaryText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        countLabel,
                        style:
                            TextStyle(fontSize: 15, color: context.primaryText),
                      ),
                      if (pendingCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemOrange
                                .resolveFrom(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (pendingCount > 0)
                    Text(
                      '$pendingCount awaiting confirmation',
                      style:
                          TextStyle(fontSize: 13, color: context.secondaryText),
                    ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 16, color: context.tertiaryText),
          ],
        ),
      ),
    );
  }
}
