import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timelines_plus/timelines_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/utils/time_format.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/events_repository.dart';
import '../data/models/event_detail.dart';
import '../data/models/event_member.dart';
import '../data/models/sub_entry.dart';
import '../providers/events_provider.dart';
import 'attachment_widgets.dart';

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
          message: ErrorView.friendlyMessage(e),
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
                onPressed: () =>
                    context.push('/events/${event.key}/edit', extra: event),
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
              trailing: StatusChip(status: event.status!),
            ),
          ],

          // Event type + flags row
          if (_hasFlags) ...[
            const SizedBox(height: 16),
            _FlagsRow(event: event),
          ],

          // Timeline
          if (event.timeline.isNotEmpty || event.time != null) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Timeline'),
            const SizedBox(height: 8),
            _TimelineSection(
              entries: event.timeline,
              eventDate: event.parsedDate,
              showTime: event.time,
              eventDateStr: event.date,
            ),
          ],

          // Notes
          if (event.notes != null && event.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Notes'),
            const SizedBox(height: 8),
            _NotesBox(html: event.notes!),
          ],

          // Attachments
          if (event.attachments.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Attachments'),
            const SizedBox(height: 8),
            _AttachmentsSection(attachments: event.attachments),
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
          if (event.lodging.isNotEmpty &&
              event.lodging.any((l) => l.title == 'Provided' && l.data == true)) ...[
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

          // Roster
          if (event.members.isNotEmpty) ...[
            const SizedBox(height: 20),
            _RosterSection(event: event),
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

  String _formatDateAndTime(String date, String? time) =>
      formatDateWithTimeRange(date, time, null);
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

class _TimelineSection extends StatefulWidget {
  const _TimelineSection({
    required this.entries,
    required this.eventDate,
    this.showTime,
    this.eventDateStr,
  });
  final List<EventTimelineEntry> entries;
  final DateTime eventDate;
  final String? showTime;
  final String? eventDateStr;

  @override
  State<_TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<_TimelineSection> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  List<({bool isShowTime, EventTimelineEntry entry})> _buildRows() {
    final rows = <({bool isShowTime, EventTimelineEntry entry})>[
      for (final e in widget.entries) (isShowTime: false, entry: e),
    ];
    if (widget.showTime != null && widget.eventDateStr != null) {
      rows.add((
        isShowTime: true,
        entry: EventTimelineEntry(title: 'Show Time', time: '${widget.eventDateStr} ${widget.showTime}'),
      ));
    }
    rows.sort((a, b) {
      final aTime = a.entry.time;
      final bTime = b.entry.time;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final aDt = DateTime.tryParse(aTime);
      final bDt = DateTime.tryParse(bTime);
      if (aDt == null || bDt == null) return aTime.compareTo(bTime);
      return aDt.compareTo(bDt);
    });
    return rows;
  }

  // Returns the index of the "active" row: the last row whose time <= now,
  // as long as the next row hasn't started yet (or it's the last row).
  int _activeIndex(List<({bool isShowTime, EventTimelineEntry entry})> rows) {
    int active = -1;
    for (int i = 0; i < rows.length; i++) {
      final t = rows[i].entry.time;
      if (t == null) continue;
      final dt = DateTime.tryParse(t);
      if (dt != null && !dt.isAfter(_now)) active = i;
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = CupertinoColors.activeBlue.resolveFrom(context);
    final connectorColor = CupertinoColors.separator.resolveFrom(context);
    final rows = _buildRows();
    final activeIdx = _activeIndex(rows);

    return _Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FixedTimeline.tileBuilder(
          theme: TimelineThemeData(
            nodePosition: 0.02,
            color: accentColor,
            indicatorTheme: const IndicatorThemeData(size: 10, position: 0.5),
            connectorTheme: ConnectorThemeData(thickness: 5, color: connectorColor),
          ),
          builder: TimelineTileBuilder.connected(
            itemCount: rows.length,
            contentsBuilder: (context, i) {
              final row = rows[i];
              final isPin = row.isShowTime;
              final isPast = activeIdx >= 0 && i < activeIdx;
              final isCurrent = i == activeIdx;
              final Color labelColor;
              final Color timeColor;
              if (isCurrent) {
                labelColor = accentColor;
                timeColor = accentColor;
              } else if (isPast) {
                labelColor = CupertinoColors.tertiaryLabel.resolveFrom(context);
                timeColor = CupertinoColors.tertiaryLabel.resolveFrom(context);
              } else if (isPin) {
                labelColor = accentColor;
                timeColor = accentColor;
              } else {
                labelColor = CupertinoColors.label.resolveFrom(context);
                timeColor = CupertinoColors.secondaryLabel.resolveFrom(context);
              }

              return Padding(
                padding: const EdgeInsets.only(top: 10, right: 0, left: 10, bottom: 10),
                child: Row(
                  children: [
                    Text(
                      toAmPm(row.entry.time, fallback: '—'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Menlo',
                        color: timeColor,
                        decoration: isPast ? TextDecoration.lineThrough : null,
                        decorationColor: timeColor,
                      ),
                    ),
                    if (isNextDay(row.entry.time, widget.eventDate)) ...[
                      const SizedBox(width: 4),
                      const NextDayBadge(),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.entry.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: (isPin || isCurrent) ? FontWeight.w600 : FontWeight.w400,
                          color: labelColor,
                          decoration: isPast ? TextDecoration.lineThrough : null,
                          decorationColor: labelColor,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NOW',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
            indicatorBuilder: (context, i) {
              final isPast = activeIdx >= 0 && i < activeIdx;
              final isCurrent = i == activeIdx;
              final color = (isPast)
                  ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                  : accentColor;
              return DotIndicator(
                color: color,
                size: isCurrent ? 13 : 10,
                border: isCurrent
                    ? Border.all(color: accentColor, width: 2)
                    : null,
              );
            },
            connectorBuilder: (context, i, type) {
              final isPast = activeIdx >= 0 && i < activeIdx;
              final color = isPast
                  ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                  : connectorColor;
              return SolidLineConnector(color: color, thickness: 1.5);
            },
          ),
        ),
      ),
    );
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

// ── Attachments ───────────────────────────────────────────────────────────────

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({required this.attachments});
  final List<EventAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    // Collect image-only attachments so we can pass the correct PageView index.
    final imageAttachments = attachments
        .where((a) => a.mimeType.startsWith('image/'))
        .toList();

    return _Card(
      child: Column(
        children: [
          for (int i = 0; i < attachments.length; i++) ...[
            if (i > 0)
              Container(
                height: 0.5,
                color: CupertinoColors.separator.resolveFrom(context),
              ),
            _AttachmentRow(
              attachment: attachments[i],
              imageAttachments: imageAttachments,
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.imageAttachments,
  });
  final EventAttachment attachment;

  /// All image attachments in the parent list — used to resolve the lightbox
  /// start index when this row is an image.
  final List<EventAttachment> imageAttachments;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final resolvedUrl = resolveAttachmentUrl(attachment.url);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => _handleTap(context, isImage, resolvedUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Thumbnail for images, icon for everything else
            SizedBox(
              width: 40,
              height: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: isImage && resolvedUrl.isNotEmpty
                    ? AuthThumbnail(url: resolvedUrl)
                    : ColoredBox(
                        color: CupertinoColors.systemBlue
                            .resolveFrom(context)
                            .withValues(alpha: 0.12),
                        child: Center(
                          child: Icon(
                            attachmentIcon(attachment.mimeType),
                            size: 22,
                            color: CupertinoColors.systemBlue
                                .resolveFrom(context),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.filename,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    attachment.formattedSize,
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, bool isImage, String resolvedUrl) {
    if (isImage && imageAttachments.isNotEmpty) {
      // Find this attachment's index within the image-only list.
      final startIndex = imageAttachments.indexWhere((a) => a.id == attachment.id);
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AttachmentLightbox(
            attachments: imageAttachments,
            startIndex: startIndex < 0 ? 0 : startIndex,
          ),
        ),
      );
    } else {
      if (resolvedUrl.isEmpty) return;
      final uri = Uri.tryParse(resolvedUrl);
      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ── Roster ────────────────────────────────────────────────────────────────────

/// Groups members by role and provides sub-assignment actions.
/// Must be a ConsumerWidget because it reads providers for sub assignment.
class _RosterSection extends ConsumerStatefulWidget {
  const _RosterSection({required this.event});
  final EventDetail event;

  @override
  ConsumerState<_RosterSection> createState() => _RosterSectionState();
}

class _RosterSectionState extends ConsumerState<_RosterSection> {
  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    // Group members by section (BandRole), preserving insertion order.
    final grouped = <String, List<EventMember>>{};
    for (final m in event.members) {
      (grouped[m.groupKey] ??= []).add(m);
    }

    final statusColor = switch (event.rosterStatus) {
      'green' => CupertinoColors.systemGreen,
      'yellow' => CupertinoColors.systemOrange,
      'red' => CupertinoColors.systemRed,
      _ => CupertinoColors.systemGrey,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with roster status dot
        Row(
          children: [
            const Text(
              'Roster',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            if (event.rosterStatus != null &&
                event.rosterStatus != 'none' &&
                event.rosterStatus!.isNotEmpty)
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor.resolveFrom(context),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...grouped.entries.map(
          (entry) => _RoleGroup(
            role: entry.key,
            members: entry.value,
            event: event,
            onAssignSub: (member) => _showSubPicker(member),
          ),
        ),
      ],
    );
  }

  Future<void> _showSubPicker(EventMember member) async {
    if (member.bandRoleId == null) return;
    final event = widget.event;

    final result = await showCupertinoModalPopup<_SubPickerResult>(
      context: context,
      builder: (_) => _SubPickerSheet(event: event, member: member),
    );

    if (result == null || !mounted) return;

    final repo = ref.read(eventsRepositoryProvider);
    // For synthetic slots (no EventMember row yet), memberId = 0 triggers creation.
    final memberId = member.id ?? 0;

    if (result.clear) {
      await repo.assignSub(event.key, memberId, slotId: member.slotId, clear: true);
    } else if (result.sub != null) {
      final sub = result.sub!;
      await repo.assignSub(
        event.key,
        memberId,
        slotId: member.slotId,
        rosterMemberId: sub.rosterMemberId,
        name: sub.rosterMemberId == null ? sub.name : null,
        email: sub.rosterMemberId == null ? sub.email : null,
      );
    }

    if (mounted) {
      ref.invalidate(eventDetailProvider(event.key));
    }
  }
}

class _RoleGroup extends StatelessWidget {
  const _RoleGroup({
    required this.role,
    required this.members,
    required this.event,
    required this.onAssignSub,
  });
  final String role;
  final List<EventMember> members;
  final EventDetail event;
  final void Function(EventMember) onAssignSub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            role.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
        ...members.map(
          (m) => _MemberTile(
            member: m,
            canWrite: event.canWrite,
            onTap: event.canWrite ? () => onAssignSub(m) : null,
          ),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canWrite,
    this.onTap,
  });
  final EventMember member;
  final bool canWrite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final slotLabel = member.slotName;

    if (!member.isFilled) {
      // Unfilled slot — placeholder row with instrument label + add button
      return GestureDetector(
        onTap: canWrite ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed
                      .resolveFrom(context)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: CupertinoColors.systemRed
                        .resolveFrom(context)
                        .withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  CupertinoIcons.question_circle,
                  size: 18,
                  color: CupertinoColors.systemRed.resolveFrom(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (slotLabel != null)
                      Text(
                        slotLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    Text(
                      '— Needed',
                      style: TextStyle(
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (canWrite)
                Icon(
                  CupertinoIcons.add_circled,
                  size: 22,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
            ],
          ),
        ),
      );
    }

    // Filled slot
    final (icon, iconColor) = switch (member.attendanceStatus?.toLowerCase()) {
      'confirmed' => (
          CupertinoIcons.checkmark_circle_fill,
          CupertinoColors.systemGreen
        ),
      'absent' => (CupertinoIcons.xmark_circle_fill, CupertinoColors.systemRed),
      _ => (CupertinoIcons.circle, CupertinoColors.systemGrey),
    };

    return GestureDetector(
      onTap: canWrite ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground
                    .resolveFrom(context),
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
                  if (slotLabel != null)
                    Text(
                      slotLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (member.isSub) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemOrange
                                .resolveFrom(context)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: CupertinoColors.systemOrange
                                  .resolveFrom(context)
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'Sub',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.systemOrange
                                  .resolveFrom(context),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(icon, size: 20, color: iconColor.resolveFrom(context)),
          ],
        ),
      ),
    );
  }
}

// ── Sub picker sheet ──────────────────────────────────────────────────────────

/// Return value from [_SubPickerSheet].
/// [sub] is set when a sub was selected; [clear] is true when the slot should
/// be cleared. Both null / false means the user dismissed without acting.
class _SubPickerResult {
  const _SubPickerResult({this.sub, this.clear = false});
  final SubEntry? sub;
  final bool clear;
}

/// Bottom sheet showing the substitute call list for a roster slot.
/// Pops with a [_SubPickerResult] so the caller controls all async work.
class _SubPickerSheet extends ConsumerWidget {
  const _SubPickerSheet({required this.event, required this.member});

  final EventDetail event;
  final EventMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(
      eventSubsProvider(
          (eventKey: event.key, bandRoleId: member.bandRoleId!)),
    );

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Sheet title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add Sub \u2014 ${member.slotName ?? member.role ?? 'Member'}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                if (member.isFilled)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context)
                        .pop(const _SubPickerResult(clear: true)),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                          color: CupertinoColors.systemRed.resolveFrom(context)),
                    ),
                  ),
                CupertinoButton(
                  padding: const EdgeInsets.only(left: 8),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(CupertinoIcons.xmark_circle_fill, size: 24),
                ),
              ],
            ),
          ),
          Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context)),
          // Sub list
          Expanded(
            child: subsAsync.when(
              loading: () =>
                  const Center(child: CupertinoActivityIndicator()),
              error: (e, _) => Center(
                child: Text(
                  ErrorView.friendlyMessage(e),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context)),
                ),
              ),
              data: (subs) {
                if (subs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No substitutes on call list for this role.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: CupertinoColors.secondaryLabel),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: subs.length,
                  separatorBuilder: (_, __) => Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 16),
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  itemBuilder: (context, index) {
                    final sub = subs[index];
                    return CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      onPressed: () => Navigator.of(context)
                          .pop(_SubPickerResult(sub: sub)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      sub.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: CupertinoColors.label
                                            .resolveFrom(context),
                                      ),
                                    ),
                                    if (sub.isCustom) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: CupertinoColors.systemOrange
                                              .resolveFrom(context)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Sub',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: CupertinoColors.systemOrange
                                                .resolveFrom(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (sub.email != null && sub.email!.isNotEmpty)
                                  Text(
                                    sub.email!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: CupertinoColors.secondaryLabel
                                          .resolveFrom(context),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            CupertinoIcons.add,
                            size: 20,
                            color:
                                CupertinoColors.systemGreen.resolveFrom(context),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
