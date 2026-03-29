import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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
          // Date / Time
          _InfoRow(
            icon: CupertinoIcons.calendar,
            label: 'Date',
            value: _formatDateAndTime(event.date, event.time),
          ),

          // Venue
          if (event.venueName != null && event.venueName!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: CupertinoIcons.location,
              label: 'Venue',
              value: [
                event.venueName!,
                if (event.venueAddress != null && event.venueAddress!.isNotEmpty)
                  event.venueAddress!,
              ].join('\n'),
            ),
          ],

          // Status
          if (event.status != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: CupertinoIcons.info_circle,
              label: 'Status',
              value: '',
              trailing: _StatusChip(status: event.status!),
            ),
          ],

          // Event type + flags row
          if (_hasFlags) ...[
            const SizedBox(height: 16),
            _FlagsRow(event: event),
          ],

          // Timeline
          if (event.timeline.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Timeline'),
            const SizedBox(height: 8),
            _TimelineSection(entries: event.timeline),
          ],

          // Notes
          if (event.notes != null && event.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Notes'),
            const SizedBox(height: 8),
            _NotesBox(html: event.notes!),
          ],

          // Attire
          if (event.attire != null && event.attire!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Attire'),
            const SizedBox(height: 8),
            _Card(child: Text(event.attire!, style: const TextStyle(fontSize: 15))),
          ],

          // Live setlist button
          if (event.liveSessionId != null) ...[
            const SizedBox(height: 20),
            _LiveSetlistButton(eventKey: event.key),
          ],

          // Performance (songs / charts)
          if (event.performance != null &&
              (event.performance!.notes?.isNotEmpty == true ||
                  event.performance!.songs.isNotEmpty ||
                  event.performance!.charts.isNotEmpty)) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Performance'),
            const SizedBox(height: 8),
            _PerformanceSection(performance: event.performance!),
          ],

          // Wedding details
          if (event.wedding != null &&
              (event.wedding!.onsite != null || event.wedding!.dances.isNotEmpty)) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Wedding Details'),
            const SizedBox(height: 8),
            _WeddingSection(wedding: event.wedding!),
          ],

          // Lodging
          if (event.lodging.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Lodging'),
            const SizedBox(height: 8),
            _LodgingSection(items: event.lodging),
          ],

          // Contacts
          if (event.contacts.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Contacts'),
            const SizedBox(height: 8),
            ...event.contacts.map((c) => _ContactRow(contact: c)),
          ],

          // Members
          if (event.members.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Members'),
            const SizedBox(height: 8),
            ...event.members.map((m) => _MemberRow(member: m)),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  bool get _hasFlags =>
      event.isPublic != null ||
      event.outside != null ||
      event.backlineProvided != null ||
      event.productionNeeded != null;

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

// ── Reusable layout helpers ───────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

// ── Info row (icon + label + value) ──────────────────────────────────────────

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
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
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

// ── Status chip ───────────────────────────────────────────────────────────────

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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Flags row ─────────────────────────────────────────────────────────────────

class _FlagsRow extends StatelessWidget {
  const _FlagsRow({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (event.isPublic != null) {
      chips.add(_FlagChip(
        label: event.isPublic! ? 'Public' : 'Private',
        icon: event.isPublic! ? CupertinoIcons.globe : CupertinoIcons.lock,
        active: event.isPublic!,
      ));
    }
    if (event.outside != null) {
      chips.add(_FlagChip(
        label: 'Outdoor',
        icon: CupertinoIcons.sun_max,
        active: event.outside!,
      ));
    }
    if (event.backlineProvided != null) {
      chips.add(_FlagChip(
        label: 'Backline',
        icon: CupertinoIcons.music_note_2,
        active: event.backlineProvided!,
      ));
    }
    if (event.productionNeeded != null) {
      chips.add(_FlagChip(
        label: 'Production',
        icon: CupertinoIcons.bolt,
        active: event.productionNeeded!,
      ));
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.label, required this.icon, required this.active});
  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? CupertinoColors.systemBlue.resolveFrom(context)
        : CupertinoColors.systemGrey.resolveFrom(context);
    final bg = active
        ? CupertinoColors.systemBlue.resolveFrom(context).withValues(alpha: 0.12)
        : CupertinoColors.systemGrey5.resolveFrom(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Timeline ──────────────────────────────────────────────────────────────────

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({required this.entries});
  final List<EventTimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      _formatTime(entries[i].time),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Menlo',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entries[i].title,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      // Try "HH:mm" or "HH:mm:ss"
      try {
        final parts = raw.split(':');
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final dt = DateTime(2000, 1, 1, h, m);
        return DateFormat('h:mm a').format(dt);
      } catch (_) {
        return raw;
      }
    }
  }
}

// ── Notes ─────────────────────────────────────────────────────────────────────

class _NotesBox extends StatelessWidget {
  const _NotesBox({required this.html});
  final String html;

  @override
  Widget build(BuildContext context) {
    // Strip basic HTML tags for display
    final plain = html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '')
        .replaceAll('</p>', '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    return _Card(child: Text(plain, style: const TextStyle(fontSize: 15)));
  }
}

// ── Live setlist button ───────────────────────────────────────────────────────

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

// ── Performance ───────────────────────────────────────────────────────────────

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({required this.performance});
  final Performance performance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (performance.notes != null && performance.notes!.isNotEmpty) ...[
          _Card(child: Text(performance.notes!, style: const TextStyle(fontSize: 15))),
          const SizedBox(height: 8),
        ],
        if (performance.songs.isNotEmpty) ...[
          Text('Songs',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
          const SizedBox(height: 6),
          _Card(
            child: Column(
              children: [
                for (int i = 0; i < performance.songs.length; i++) ...[
                  if (i > 0)
                    Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
                  _SongRow(index: i + 1, song: performance.songs[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (performance.charts.isNotEmpty) ...[
          Text('Charts',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
          const SizedBox(height: 6),
          _Card(
            child: Column(
              children: [
                for (int i = 0; i < performance.charts.length; i++) ...[
                  if (i > 0)
                    Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
                  _ChartRow(chart: performance.charts[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.index, required this.song});
  final int index;
  final PerformanceSong song;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$index.',
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (song.title != null && song.title!.isNotEmpty)
                  Text(song.title!, style: const TextStyle(fontSize: 15)),
                if (song.url != null && song.url!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _launch(song.url!),
                    child: Text(
                      song.url!,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.activeBlue.resolveFrom(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ChartRow extends StatelessWidget {
  const _ChartRow({required this.chart});
  final PerformanceChart chart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(CupertinoIcons.doc_text,
              size: 16,
              color: CupertinoColors.secondaryLabel.resolveFrom(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chart.title, style: const TextStyle(fontSize: 15)),
                if (chart.composer != null && chart.composer!.isNotEmpty)
                  Text(chart.composer!,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Wedding ───────────────────────────────────────────────────────────────────

class _WeddingSection extends StatelessWidget {
  const _WeddingSection({required this.wedding});
  final WeddingDetail wedding;

  @override
  Widget build(BuildContext context) {
    return _Card(
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
            Container(height: 0.5, margin: const EdgeInsets.symmetric(vertical: 10), color: CupertinoColors.separator.resolveFrom(context)),
          ],
          if (wedding.dances.isNotEmpty) ...[
            Text(
              'Special Dances',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < wedding.dances.length; i++) ...[
              if (i > 0)
                Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
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
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context)),
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

// ── Lodging ───────────────────────────────────────────────────────────────────

class _LodgingSection extends StatelessWidget {
  const _LodgingSection({required this.items});
  final List<LodgingItem> items;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items[i].type == 'checkbox')
                    Icon(
                      items[i].data == true
                          ? CupertinoIcons.checkmark_square_fill
                          : CupertinoIcons.square,
                      size: 18,
                      color: items[i].data == true
                          ? CupertinoColors.systemGreen.resolveFrom(context)
                          : CupertinoColors.secondaryLabel.resolveFrom(context),
                    )
                  else
                    Icon(CupertinoIcons.bed_double,
                        size: 18,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].title,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500)),
                        if (items[i].type == 'text' &&
                            items[i].data != null &&
                            items[i].data.toString().isNotEmpty)
                          Text(items[i].data.toString(),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Contacts ──────────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});
  final EventContact contact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CupertinoColors.systemBlue
                    .resolveFrom(context)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.systemBlue.resolveFrom(context)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  if (contact.role != null && contact.role!.isNotEmpty)
                    Text(contact.role!,
                        style: TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.secondaryLabel.resolveFrom(context))),
                  if (contact.phone != null && contact.phone!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _ContactLink(
                      icon: CupertinoIcons.phone,
                      label: contact.phone!,
                      url: 'tel:${contact.phone!}',
                      context: context,
                    ),
                  ],
                  if (contact.email != null && contact.email!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _ContactLink(
                      icon: CupertinoIcons.mail,
                      label: contact.email!,
                      url: 'mailto:${contact.email!}',
                      context: context,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactLink extends StatelessWidget {
  const _ContactLink({
    required this.icon,
    required this.label,
    required this.url,
    required this.context,
  });
  final IconData icon;
  final String label;
  final String url;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri);
      },
      child: Row(
        children: [
          Icon(icon,
              size: 13,
              color: CupertinoColors.activeBlue.resolveFrom(ctx)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.activeBlue.resolveFrom(ctx)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Members ───────────────────────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});
  final EventMember member;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (member.attendanceStatus?.toLowerCase()) {
      'confirmed' => (CupertinoIcons.checkmark_circle, CupertinoColors.systemGreen),
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
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
