import 'package:flutter/cupertino.dart';
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
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(),
        child: ErrorView(
          message: 'Could not load event.\n$e',
          onRetry: () => ref.invalidate(eventDetailProvider(eventKey)),
        ),
      ),
      data: (event) => _EventDetailView(event: event),
    );
  }
}

class _EventDetailView extends StatelessWidget {
  const _EventDetailView({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(event.title),
        trailing: event.canWrite
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  showCupertinoDialog(
                    context: context,
                    builder: (_) => CupertinoAlertDialog(
                      title: const Text('Edit Event'),
                      content: const Text('Edit event — coming soon.'),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('OK'),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  );
                },
                child: const Icon(CupertinoIcons.pencil),
              )
            : null,
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoRow(
            icon: CupertinoIcons.calendar,
            label: 'Date',
            value: _formatDateAndTime(event.date, event.time),
          ),
          if (event.venueName != null && event.venueName!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: CupertinoIcons.location,
              label: 'Venue',
              value: [
                event.venueName!,
                if (event.venueAddress != null &&
                    event.venueAddress!.isNotEmpty)
                  event.venueAddress!,
              ].join('\n'),
            ),
          ],
          if (event.status != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: CupertinoIcons.info_circle,
              label: 'Status',
              value: '',
              trailing: _StatusChip(status: event.status!),
            ),
          ],
          if (event.notes != null && event.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Notes',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(event.notes!, style: const TextStyle(fontSize: 15)),
            ),
          ],
          if (event.liveSessionId != null) ...[
            const SizedBox(height: 20),
            _LiveSetlistButton(eventKey: event.key),
          ],
          if (event.members.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Members',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...event.members.map((member) => _MemberRow(member: member)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _formatDateAndTime(String date, String? time) {
    try {
      final dt = DateTime.parse(date);
      final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(dt);
      if (time != null && time.isNotEmpty) return '$dateStr at $time';
      return dateStr;
    } catch (_) {
      return time != null ? '$date at $time' : date;
    }
  }
}

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context))),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status.toLowerCase()) {
      'confirmed' => (
          'Confirmed',
          CupertinoColors.systemGreen.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemGreen.resolveFrom(context),
        ),
      'pending' => (
          'Pending',
          CupertinoColors.systemOrange.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemOrange.resolveFrom(context),
        ),
      'cancelled' || 'canceled' => (
          'Cancelled',
          CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemRed.resolveFrom(context),
        ),
      _ => (
          status,
          CupertinoColors.systemGrey5.resolveFrom(context),
          CupertinoColors.systemGrey.resolveFrom(context),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _LiveSetlistButton extends StatelessWidget {
  const _LiveSetlistButton({required this.eventKey});
  final String eventKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        onPressed: () => context.push('/events/$eventKey/setlist/live'),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.music_note, size: 18),
            SizedBox(width: 8),
            Text('Join Live Setlist'),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});
  final EventMember member;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (member.attendanceStatus?.toLowerCase()) {
      'confirmed' => (
          CupertinoIcons.checkmark_circle,
          CupertinoColors.systemGreen
        ),
      'absent' => (CupertinoIcons.xmark_circle, CupertinoColors.systemRed),
      _ => (CupertinoIcons.question_circle, CupertinoColors.systemOrange),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                if (member.role != null && member.role!.isNotEmpty)
                  Text(member.role!,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context))),
              ],
            ),
          ),
          Icon(icon, size: 20, color: color),
        ],
      ),
    );
  }
}
