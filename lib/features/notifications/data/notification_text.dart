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

/// Formats a time string as `h:mma` in lowercase (e.g. `2:00pm`).
/// Returns null when the value cannot be parsed.
String? formatClock(String? value) {
  final t = parseEntryTime(value);
  if (t == null) return null;
  final isPm = t.hour >= 12;
  var hour12 = t.hour % 12;
  if (hour12 == 0) hour12 = 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final suffix = isPm ? 'pm' : 'am';
  return '$hour12:$minute$suffix';
}

/// Builds the 8h-reminder body (Phase 1: no travel "leave by" lines).
///
/// - [venue]: venue name/address, or null if none/ungeocodable.
/// - [firstItemTitle]/[firstItemTime]: the earliest timeline item, if any.
/// - [showTime]: the event's startTime, if any.
String buildReminderBody({
  required String? venue,
  required String? firstItemTitle,
  required String? firstItemTime,
  required String? showTime,
}) {
  final lines = <String>[];

  final firstClock = formatClock(firstItemTime);
  if (firstItemTitle != null && firstClock != null) {
    lines.add('$firstItemTitle $firstClock');
  }

  final showClock = formatClock(showTime);
  // Only add a distinct "Show" line when it differs from the first item time.
  if (showClock != null && showClock != firstClock) {
    lines.add('Show $showClock');
  }

  final core = lines.isEmpty ? 'You have an event today' : lines.join(', ');

  if (venue != null && venue.isNotEmpty) {
    return '$venue · $core';
  }
  return core;
}
