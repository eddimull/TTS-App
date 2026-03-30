import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../events/data/models/event_summary.dart';
import '../../../shared/utils/time_format.dart';
import '../../../shared/widgets/status_chip.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap});

  final EventSummary event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isRehearsal = event.isRehearsal;
    final bgColor = isRehearsal
        ? CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.08)
        : CupertinoColors.systemGrey6.resolveFrom(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 60,
              color: bgColor,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _EventTypeIcon(event: event),
                  if (event.liveSessionId != null) ...[
                    const SizedBox(height: 4),
                    Icon(CupertinoIcons.music_note,
                        size: 14, color: CupertinoColors.systemBlue.resolveFrom(context)),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold,
                                color: CupertinoColors.label.resolveFrom(context)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (event.status != null) StatusChip(status: event.status!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(event),
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                    ),
                    if (event.venueName != null &&
                        event.venueName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.venueName!,
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(EventSummary event) {
    final dateStr = DateFormat('EEEE, MMMM d').format(event.parsedDate);
    if (event.time != null && event.time!.isNotEmpty) {
      return '$dateStr at ${toAmPm(event.time!)}';
    }
    return dateStr;
  }

}

class _EventTypeIcon extends StatelessWidget {
  const _EventTypeIcon({required this.event});
  final EventSummary event;

  @override
  Widget build(BuildContext context) {
    final iconPath = event.gigIconPath;
    if (iconPath != null) {
      return Image.asset(iconPath, width: 40, height: 40, fit: BoxFit.contain);
    }
    return const Icon(CupertinoIcons.music_mic,
        size: 24, color: CupertinoColors.secondaryLabel);
  }
}

