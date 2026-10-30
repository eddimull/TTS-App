import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';

import '../data/event_header_times.dart';
import '../data/event_tabs.dart';
import '../data/leave_plan.dart';
import '../data/models/event_detail.dart';
import 'event_sections/flags_row.dart';
import 'event_sections/venue_card.dart';
import 'when_to_leave.dart';

/// Pinned header for the event screen: the full header (date, Load-in / Show /
/// End, venue, flags) scrolls away, then collapses to a one-line summary, and
/// the tab switcher stays pinned underneath. The tab switcher never moves
/// with the selected tab, so switching tabs can't make the header jump.
///
/// The expanded height depends on text scale and the map card, so the screen
/// measures [EventHeaderContent] and feeds the result back as
/// [contentHeight].
class EventHeaderDelegate extends SliverPersistentHeaderDelegate {
  EventHeaderDelegate({
    required this.event,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.contentHeight,
    required this.onContentMeasured,
    required this.onGoLive,
  });

  final EventDetail event;
  final List<EventTab> tabs;
  final EventTab selected;
  final ValueChanged<EventTab> onSelect;
  final double contentHeight;
  final ValueChanged<double> onContentMeasured;

  /// Gig day's Go live button.
  final VoidCallback onGoLive;

  static const double summaryHeight = 36;
  static const double tabBarHeight = 60;

  @override
  double get minExtent => summaryHeight + tabBarHeight;

  @override
  double get maxExtent => math.max(contentHeight, summaryHeight) + tabBarHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final bg = CupertinoColors.systemBackground.resolveFrom(context);
    final collapseRange = math.max(maxExtent - minExtent, 1);
    // Summary fades in over the last 24px of the collapse.
    final summaryOpacity =
        ((shrinkOffset - (collapseRange - 24)) / 24).clamp(0.0, 1.0);

    return Container(
      color: bg,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Full header scrolls up with the list; OverflowBox lets it keep its
          // natural height so it can be measured.
          Positioned(
            top: -shrinkOffset,
            left: 0,
            right: 0,
            height: math.max(contentHeight, summaryHeight),
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: MeasureSize(
                onChange: onContentMeasured,
                child: EventHeaderContent(event: event, onGoLive: onGoLive),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: summaryHeight,
            child: IgnorePointer(
              ignoring: summaryOpacity == 0,
              child: Opacity(
                opacity: summaryOpacity,
                child: Container(
                  color: bg,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    collapsedHeaderLine(event),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: tabBarHeight,
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  bottom: BorderSide(
                    color: CupertinoColors.separator.resolveFrom(context),
                    width: 0.5,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: EventTabBar(
                tabs: tabs,
                selected: selected,
                onSelect: onSelect,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant EventHeaderDelegate old) =>
      // identical, not ==: EventDetail compares by key, so a refreshed
      // event (new times, venue) would otherwise keep the stale header.
      !identical(old.event, event) ||
      old.selected != selected ||
      old.contentHeight != contentHeight ||
      !foundation.listEquals(old.tabs, tabs);
}

/// Segmented tab switcher. Segments are padded to a 44pt tap target.
class EventTabBar extends StatelessWidget {
  const EventTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<EventTab> tabs;
  final EventTab selected;
  final ValueChanged<EventTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Event sections',
      child: CupertinoSlidingSegmentedControl<EventTab>(
        groupValue: selected,
        onValueChanged: (t) {
          if (t != null) onSelect(t);
        },
        children: {
          for (final t in tabs)
            t: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              child: Text(
                t.label,
                maxLines: 1,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
        },
      ),
    );
  }
}

/// The expanded header: date, Load-in / Show / End tiles, when to leave,
/// venue map card, gig day's Directions / Go live, and flag chips.
class EventHeaderContent extends StatelessWidget {
  const EventHeaderContent({super.key, required this.event, this.onGoLive});
  final EventDetail event;
  final VoidCallback? onGoLive;

  @override
  Widget build(BuildContext context) {
    final times = headerTimes(event);
    final hasVenue = event.venueName != null && event.venueName!.isNotEmpty;
    final hasFlags = event.isPublic != null ||
        event.outside != null ||
        event.backlineProvided != null ||
        event.productionNeeded != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              _dateLabel(event),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _TimeTile(label: 'Load-in', raw: times.loadIn)),
              const SizedBox(width: 8),
              Expanded(child: _TimeTile(label: 'Show', raw: times.show)),
              const SizedBox(width: 8),
              Expanded(child: _TimeTile(label: 'End', raw: times.end)),
            ],
          ),
          // Sizes itself to nothing when the event has no leave time.
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: LeaveByRow(event: event),
          ),
          if (hasVenue) ...[
            const SizedBox(height: 12),
            VenueCard(
              venueName: event.venueName!,
              venueAddress: event.venueAddress,
            ),
          ],
          if (onGoLive != null && isLeaveDay(event, clock.now())) ...[
            const SizedBox(height: 12),
            GigDayActions(event: event, onGoLive: onGoLive!),
          ],
          if (hasFlags) ...[
            const SizedBox(height: 12),
            FlagsRow(event: event),
          ],
        ],
      ),
    );
  }

  /// "Sat, Nov 7", with the year when it isn't the current one.
  static String _dateLabel(EventDetail event) {
    final d = event.parsedDate;
    final sameYear = d.year == clock.now().year;
    return DateFormat(sameYear ? 'EEE, MMM d' : 'EEE, MMM d, y').format(d);
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.label, required this.raw});
  final String label;
  final String? raw;

  @override
  Widget build(BuildContext context) {
    final value = toAmPm(raw, fallback: '—');
    return Semantics(
      label: '$label ${raw == null ? 'not set' : value}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: context.secondaryText),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color:
                      raw == null ? context.tertiaryText : context.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reports its child's laid-out height after each layout in which it changed.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, required super.child});
  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasureSize).onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);
  ValueChanged<double> onChange;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(h));
  }
}
