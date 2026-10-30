import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/shared/widgets/status_chip.dart' show NextDayBadge;
import 'package:timelines_plus/timelines_plus.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';

// ── Timeline ──────────────────────────────────────────────────────────────────

class TimelineSection extends StatefulWidget {
  const TimelineSection({
    super.key,
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
  State<TimelineSection> createState() => _TimelineSectionState();
}

class _TimelineSectionState extends State<TimelineSection> {
  late Timer _timer;
  DateTime _now = clock.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = clock.now());
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
        entry: EventTimelineEntry(
            title: 'Show Time',
            time: '${widget.eventDateStr} ${widget.showTime}'),
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

    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FixedTimeline.tileBuilder(
          theme: TimelineThemeData(
            nodePosition: 0.02,
            color: accentColor,
            indicatorTheme: const IndicatorThemeData(size: 10, position: 0.5),
            connectorTheme:
                ConnectorThemeData(thickness: 5, color: connectorColor),
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
                padding: const EdgeInsets.only(
                    top: 10, right: 0, left: 10, bottom: 10),
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
                          fontWeight: (isPin || isCurrent)
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: labelColor,
                          decoration:
                              isPast ? TextDecoration.lineThrough : null,
                          decorationColor: labelColor,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
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
                border:
                    isCurrent ? Border.all(color: accentColor, width: 2) : null,
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
