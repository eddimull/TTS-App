import 'package:intl/intl.dart';

import '../../../shared/utils/time_format.dart';
import 'models/event_detail.dart';

/// Load-in / Show / End shown in the event header. Values are raw time strings
/// ("19:00" or "2026-04-15 19:00"), formatted by the UI; null means unknown.
class EventHeaderTimes {
  const EventHeaderTimes({this.loadIn, this.show, this.end});
  final String? loadIn;
  final String? show;
  final String? end;
}

final _loadInRe = RegExp(r'load[\s_-]*in', caseSensitive: false);
final _showRe = RegExp(r'show', caseSensitive: false);
final _startRe = RegExp(r'\bstart', caseSensitive: false);
final _endRe = RegExp(r'\b(end|ends|finish|finishes)\b', caseSensitive: false);

String? _timelineTime(
    List<EventTimelineEntry> entries, bool Function(String) match) {
  for (final e in entries) {
    final t = e.time;
    if (t != null && t.isNotEmpty && match(e.title)) return t;
  }
  return null;
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

/// Derives the header times. Show and End prefer the event's own start/end
/// fields (the same value the rest of the app shows); the timeline, matched
/// loosely by title, fills in when those are empty. Load-in only exists on
/// the timeline.
EventHeaderTimes headerTimes(EventDetail event) {
  final entries = event.timeline;

  final loadIn = _timelineTime(entries, _loadInRe.hasMatch);
  final show = _nonEmpty(event.startTime) ??
      _nonEmpty(event.time) ??
      _timelineTime(
          entries, (t) => _showRe.hasMatch(t) && !_loadInRe.hasMatch(t)) ??
      _timelineTime(
          entries, (t) => _startRe.hasMatch(t) && !_loadInRe.hasMatch(t));
  final end =
      _nonEmpty(event.endTime) ?? _timelineTime(entries, _endRe.hasMatch);

  return EventHeaderTimes(loadIn: loadIn, show: show, end: end);
}

/// One-line summary used once the header has scrolled away, e.g.
/// "Sat, Nov 7 · Show 4:30 PM · Il Mercato". Missing parts are left out.
String collapsedHeaderLine(EventDetail event) {
  final show = headerTimes(event).show;
  return [
    DateFormat('EEE, MMM d').format(event.parsedDate),
    if (show != null) 'Show ${toAmPm(show)}',
    if (event.venueName != null && event.venueName!.isNotEmpty)
      event.venueName!,
  ].join(' · ');
}
