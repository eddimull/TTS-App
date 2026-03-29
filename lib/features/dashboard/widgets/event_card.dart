import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../events/data/models/event_summary.dart';

/// A card that displays a summary of a single event.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.event,
    this.onTap,
  });

  final EventSummary event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bgColor = event.isRehearsal
        ? Colors.blue.shade50
        : Colors.purple.shade50;

    final sourceIcon = event.isRehearsal
        ? Icons.fitness_center_outlined
        : Icons.event_available_outlined;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coloured source strip.
            Container(
              width: 48,
              color: bgColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(sourceIcon, size: 20, color: colorScheme.onSurfaceVariant),
                  if (event.liveSessionId != null) ...[
                    const SizedBox(height: 6),
                    Icon(
                      Icons.music_note,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
            // Main content.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: event.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(event),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (event.venueName != null && event.venueName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.venueName!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
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
      return '$dateStr at ${event.time}';
    }
    return dateStr;
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    final (label, bg, fg) = switch (status!.toLowerCase()) {
      'confirmed' => (
          'Confirmed',
          Colors.green.shade100,
          Colors.green.shade800,
        ),
      'pending' => (
          'Pending',
          Colors.amber.shade100,
          Colors.amber.shade800,
        ),
      'cancelled' || 'canceled' => (
          'Cancelled',
          Colors.red.shade100,
          Colors.red.shade800,
        ),
      _ => (
          status!,
          Colors.grey.shade200,
          Colors.grey.shade700,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
