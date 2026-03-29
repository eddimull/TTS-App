import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/models/event_detail.dart';
import '../data/models/event_member.dart';
import '../providers/events_provider.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventKey});

  final String eventKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(eventDetailProvider(eventKey));

    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: 'Could not load event.\n$e',
          onRetry: () => ref.invalidate(eventDetailProvider(eventKey)),
        ),
      ),
      data: (event) => _EventDetailView(event: event),
    );
  }
}

// ── Detail view ───────────────────────────────────────────────────────────────

class _EventDetailView extends StatelessWidget {
  const _EventDetailView({required this.event});

  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title),
        centerTitle: false,
      ),
      floatingActionButton: event.canWrite
          ? FloatingActionButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Edit event — coming soon.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'Edit event',
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date + time.
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: _formatDateAndTime(event.date, event.time),
          ),
          // Venue.
          if (event.venueName != null && event.venueName!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Venue',
              value: [
                event.venueName!,
                if (event.venueAddress != null && event.venueAddress!.isNotEmpty)
                  event.venueAddress!,
              ].join('\n'),
            ),
          ],
          // Status.
          if (event.status != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.info_outline,
              label: 'Status',
              value: '',
              trailing: _StatusChip(status: event.status!),
            ),
          ],
          // Notes.
          if (event.notes != null && event.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Notes',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                event.notes!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          // Live setlist button.
          if (event.liveSessionId != null) ...[
            const SizedBox(height: 20),
            _LiveSetlistButton(eventKey: event.key),
          ],
          // Members.
          if (event.members.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Members',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...event.members.map(
              (member) => _MemberRow(member: member),
            ),
          ],
          // Bottom padding for FAB clearance.
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _formatDateAndTime(String date, String? time) {
    try {
      final dt = DateTime.parse(date);
      final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(dt);
      if (time != null && time.isNotEmpty) {
        return '$dateStr at $time';
      }
      return dateStr;
    } catch (_) {
      return time != null ? '$date at $time' : date;
    }
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status.toLowerCase()) {
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
          status,
          Colors.grey.shade200,
          Colors.grey.shade700,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Live setlist button ───────────────────────────────────────────────────────

class _LiveSetlistButton extends StatelessWidget {
  const _LiveSetlistButton({required this.eventKey});

  final String eventKey;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => context.push('/events/$eventKey/setlist/live'),
      icon: const Icon(Icons.music_note),
      label: const Text('Join Live Setlist'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }
}

// ── Member row ────────────────────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final EventMember member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, color) = switch (member.attendanceStatus?.toLowerCase()) {
      'confirmed' => (Icons.check_circle_outline, Colors.green.shade600),
      'absent' => (Icons.cancel_outlined, Colors.red.shade600),
      _ => (Icons.help_outline, Colors.amber.shade700),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (member.role != null && member.role!.isNotEmpty)
                  Text(
                    member.role!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Icon(icon, size: 20, color: color),
        ],
      ),
    );
  }
}
