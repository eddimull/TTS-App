import '../../events/data/models/event_detail.dart';
import 'notification_text.dart' show parseEntryTime;

/// A timeline item resolved to a concrete title + parsed [DateTime].
class FirstItem {
  const FirstItem({required this.title, required this.time});
  final String title;
  final DateTime time;
}

/// The earliest timeline entry that has a parseable time, as a [FirstItem].
/// Null when no entry qualifies. Mirrors the spec's "first item = earliest
/// time" rule, returning the parsed time the enrichment math needs.
FirstItem? resolveFirstItem(List<EventTimelineEntry> timeline) {
  FirstItem? best;
  for (final entry in timeline) {
    final t = parseEntryTime(entry.time);
    if (t == null) continue;
    if (best == null || t.isBefore(best.time)) {
      best = FirstItem(title: entry.title, time: t);
    }
  }
  return best;
}
