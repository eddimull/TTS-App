import 'package:intl/intl.dart';

import '../../rehearsals/data/models/rehearsal_schedule.dart';
import '../../rehearsals/data/models/rehearsal_summary.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Rehearsals from today up to the day before [eventDate], soonest first.
/// Cancelled rehearsals and inactive schedules are left out, as are
/// rehearsals that can't be written to (no id and no key to create one).
List<RehearsalSummary> rehearsalsBefore(
  List<RehearsalSchedule> schedules,
  DateTime eventDate,
  DateTime now,
) {
  final today = _day(now);
  final gigDay = _day(eventDate);
  final found = <RehearsalSummary>[];
  final seen = <String>{};
  for (final s in schedules) {
    if (!s.active) continue;
    for (final r in s.upcomingRehearsals) {
      final d = DateTime.tryParse(r.date ?? '');
      if (d == null || r.isCancelled) continue;
      if (r.id == null && r.eventKey == null) continue;
      final day = _day(d);
      if (day.isBefore(today) || !day.isBefore(gigDay)) continue;
      if (!seen.add('${r.id ?? r.eventKey}')) continue;
      found.add(r);
    }
  }
  found.sort((a, b) {
    final byDate = a.date!.compareTo(b.date!);
    return byDate != 0 ? byDate : (a.time ?? '').compareTo(b.time ?? '');
  });
  return found;
}

/// The line Add to rehearsal writes, e.g.
/// "Learn for Terreson Wedding (Nov 7): Here for a Good Time, Boogie Wonderland".
String learnLine(String eventTitle, DateTime eventDate, List<String> titles) =>
    'Learn for $eventTitle (${DateFormat('MMM d').format(eventDate)}): '
    '${titles.join(', ')}';

/// Rehearsal notes with a learn line appended for the [titles] not already
/// mentioned in [notes] (ignoring case). Null when every title is already
/// there.
({String notes, List<String> added})? appendLearnLine({
  required String? notes,
  required String eventTitle,
  required DateTime eventDate,
  required List<String> titles,
}) {
  final existing = (notes ?? '').toLowerCase();
  final added = <String>[];
  for (final t in titles) {
    final title = t.trim();
    if (title.isEmpty) continue;
    if (existing.contains(title.toLowerCase())) continue;
    if (added.any((a) => a.toLowerCase() == title.toLowerCase())) continue;
    added.add(title);
  }
  if (added.isEmpty) return null;
  final line = learnLine(eventTitle, eventDate, added);
  final base = (notes ?? '').trimRight();
  return (notes: base.isEmpty ? line : '$base\n$line', added: added);
}

/// "Tue, Nov 3, 7:00 PM" (time left out when unknown).
String rehearsalLabel(RehearsalSummary r) {
  final d = DateTime.tryParse(r.date ?? '');
  if (d == null) return 'the next rehearsal';
  final day = DateFormat('EEE, MMM d').format(d);
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(r.time ?? '');
  if (m == null) return day;
  final t =
      DateTime(2000, 1, 1, int.parse(m.group(1)!), int.parse(m.group(2)!));
  return '$day, ${DateFormat('h:mm a').format(t)}';
}
