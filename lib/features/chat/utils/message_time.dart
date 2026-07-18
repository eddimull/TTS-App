import 'package:intl/intl.dart';

/// Pure time-label helpers for the chat thread. Everything converts to local
/// time internally; callers pass `now` explicitly so tests can pin the clock.

/// Whether a date-separator row belongs above the message at [current], given
/// the (older) [previous] message's time. The first message of the loaded
/// window ([previous] == null) always gets one; otherwise a calendar-day
/// change or a gap of more than an hour does.
bool needsDateSeparator(DateTime? previous, DateTime current) {
  if (previous == null) return true;
  final p = previous.toLocal();
  final c = current.toLocal();
  final sameDay = p.year == c.year && p.month == c.month && p.day == c.day;
  return !sameDay || c.difference(p) > const Duration(hours: 1);
}

/// intl emits a narrow no-break space (U+202F/U+00A0) before AM/PM on
/// newer ICU data; normalize to a plain space so labels are stable.
String _clock(DateTime t) =>
    DateFormat.jm().format(t).replaceAll(RegExp(r'\s'), ' ');

/// "Today 3:42 PM" / "Yesterday 9:10 AM" / "Tuesday 6:30 PM" (last 7 days) /
/// "Jun 3, 2026 3:42 PM" (older).
String dateSeparatorLabel(DateTime time, {required DateTime now}) {
  final t = time.toLocal();
  final n = now.toLocal();
  final clock = _clock(t);
  final daysAgo = DateTime(n.year, n.month, n.day)
      .difference(DateTime(t.year, t.month, t.day))
      .inDays;
  if (daysAgo <= 0) return 'Today $clock';
  if (daysAgo == 1) return 'Yesterday $clock';
  if (daysAgo < 7) return '${DateFormat.EEEE().format(t)} $clock';
  return '${DateFormat.yMMMd().format(t)} $clock';
}

/// Tap-to-reveal label under a bubble: time only for today's messages, full
/// date + time otherwise.
String bubbleTimeLabel(DateTime time, {required DateTime now}) {
  final t = time.toLocal();
  final n = now.toLocal();
  final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  final clock = _clock(t);
  return sameDay ? clock : '${DateFormat.yMMMd().format(t)} $clock';
}
