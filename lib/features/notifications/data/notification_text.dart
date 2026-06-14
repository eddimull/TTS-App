import '../../events/data/models/event_detail.dart';

/// Parses an ISO-8601 or `HH:mm` time string into a comparable [DateTime].
/// Returns null when the value is missing or unparseable.
DateTime? parseEntryTime(String? value) {
  if (value == null || value.isEmpty) return null;
  // Full ISO timestamp (e.g. 2026-06-13T14:00:00).
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso;
  // Bare HH:mm — anchor to a fixed reference date so entries are comparable.
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (match != null) {
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    return DateTime(2000, 1, 1, h, m);
  }
  return null;
}

/// The timeline entry with the earliest parseable [EventTimelineEntry.time].
/// Entries without a parseable time are ignored. Null if none qualify.
EventTimelineEntry? firstTimelineItem(List<EventTimelineEntry> timeline) {
  EventTimelineEntry? best;
  DateTime? bestTime;
  for (final entry in timeline) {
    final t = parseEntryTime(entry.time);
    if (t == null) continue;
    if (bestTime == null || t.isBefore(bestTime)) {
      best = entry;
      bestTime = t;
    }
  }
  return best;
}
