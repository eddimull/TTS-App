import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/event_detail.dart';
import '../../../shared/utils/time_format.dart';

/// At-a-glance summary card shown on the event detail screen, just under the
/// flags row. Surfaces the show time, a tap-to-expand attire line, and a link
/// to the event's first lodging stay (when present). Rows render only when
/// their underlying data exists; the whole card is omitted when none do.
class EventGlanceCard extends StatefulWidget {
  const EventGlanceCard({
    super.key,
    required this.event,
    this.onShowTimeTap,
    this.onLodgingTap,
  });

  final EventDetail event;

  /// Invoked when the show-time row is tapped (scrolls to the Timeline
  /// section on the parent screen).
  final VoidCallback? onShowTimeTap;

  /// Invoked when the lodging row is tapped, with the tapped lodging's id.
  final void Function(int lodgingId)? onLodgingTap;

  /// Whether [event] has any data the glance card would render. Callers can
  /// use this to skip the spacing they'd otherwise reserve for the card.
  static bool hasContent(EventDetail event) =>
      (event.time != null && event.time!.isNotEmpty) ||
      (event.attire != null && event.attire!.isNotEmpty) ||
      event.lodgings.isNotEmpty;

  @override
  State<EventGlanceCard> createState() => _EventGlanceCardState();
}

class _EventGlanceCardState extends State<EventGlanceCard> {
  bool _attireExpanded = false;

  bool get _hasShowTime =>
      widget.event.time != null && widget.event.time!.isNotEmpty;

  bool get _hasAttire =>
      widget.event.attire != null && widget.event.attire!.isNotEmpty;

  bool get _hasLodging => widget.event.lodgings.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasShowTime && !_hasAttire && !_hasLodging) {
      return const SizedBox.shrink();
    }

    final separatorColor = CupertinoColors.separator.resolveFrom(context);
    final rows = <Widget>[];

    if (_hasShowTime) {
      rows.add(_buildShowTimeRow(context));
    }
    if (_hasAttire) {
      if (rows.isNotEmpty) rows.add(_separator(separatorColor));
      rows.add(_buildAttireRow(context));
    }
    if (_hasLodging) {
      if (rows.isNotEmpty) rows.add(_separator(separatorColor));
      rows.add(_buildLodgingRow(context));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _separator(Color color) => Container(height: 0.5, color: color);

  Widget _buildShowTimeRow(BuildContext context) {
    final event = widget.event;
    final showTime = toAmPm(event.time);
    final hasEndTime = event.endTime != null && event.endTime!.isNotEmpty;

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 10),
      minimumSize: Size.zero,
      onPressed: widget.onShowTimeTap,
      child: Row(
        children: [
          Icon(CupertinoIcons.clock, size: 18, color: context.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Show $showTime',
              style: TextStyle(fontSize: 15, color: context.primaryText),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasEndTime)
            Text(
              'ends ${toAmPm(event.endTime)}',
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
        ],
      ),
    );
  }

  Widget _buildAttireRow(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _attireExpanded = !_attireExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.tag, size: 18, color: context.secondaryText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Attire',
                    style: TextStyle(fontSize: 15, color: context.primaryText),
                  ),
                ),
                AnimatedRotation(
                  turns: _attireExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(CupertinoIcons.chevron_down,
                      size: 16, color: context.tertiaryText),
                ),
              ],
            ),
            if (_attireExpanded) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  widget.event.attire!,
                  style: TextStyle(fontSize: 14, color: context.secondaryText),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLodgingRow(BuildContext context) {
    final lodging = widget.event.lodgings.first;

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 10),
      minimumSize: Size.zero,
      onPressed: widget.onLodgingTap == null
          ? null
          : () => widget.onLodgingTap!(lodging.id),
      child: Row(
        children: [
          Icon(CupertinoIcons.bed_double, size: 18, color: context.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              lodging.name,
              style: TextStyle(fontSize: 15, color: context.primaryText),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 16, color: context.tertiaryText),
        ],
      ),
    );
  }
}
