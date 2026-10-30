import 'package:intl/intl.dart';

import 'event_header_times.dart';
import 'models/event_detail.dart';

/// Where the drive to the gig starts.
enum LeaveStart {
  home('Home'),
  gearPickup('Gear pickup'),
  hotel('Hotel'),
  here('Where I am now');

  const LeaveStart(this.label);
  final String label;
}

const Duration defaultEarlyBy = Duration(minutes: 10);

/// The time the drive has to make, e.g. the 2:30 load-in.
class LeaveTarget {
  const LeaveTarget({required this.label, required this.at});

  /// "load-in" or "show".
  final String label;
  final DateTime at;
}

final _timeRe = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?$');

/// The clock time of a header time ("19:00" or "2026-04-15 19:00") on the
/// event's [date]. Any date in the raw value is ignored: timeline dates are
/// sometimes left over from another year, and a load-in or show is on the
/// day of the gig.
DateTime? _onDate(DateTime date, String? raw) {
  final m = _timeRe.firstMatch(raw?.trim() ?? '');
  if (m == null) return null;
  return DateTime(date.year, date.month, date.day, int.parse(m.group(1)!),
      int.parse(m.group(2)!));
}

/// Load-in when the event has one, otherwise the show. Null when neither has
/// a time.
LeaveTarget? leaveTarget(EventDetail event) {
  final times = headerTimes(event);
  final date = event.parsedDate;
  final loadIn = _onDate(date, times.loadIn);
  if (loadIn != null) return LeaveTarget(label: 'load-in', at: loadIn);
  final show = _onDate(date, times.show);
  if (show != null) return LeaveTarget(label: 'show', at: show);
  return null;
}

/// When to leave: [arriveBy] minus [earlyBy] minus [drive], rounded down to
/// five minutes so "~" never promises a later time than the maths.
DateTime leaveBy({
  required DateTime arriveBy,
  required Duration earlyBy,
  required Duration drive,
}) {
  final t = arriveBy.subtract(earlyBy).subtract(drive);
  final floored = t.minute - t.minute % 5;
  return DateTime(t.year, t.month, t.day, t.hour, floored);
}

/// Drive time rounded up to five minutes, at least five.
Duration roundDrive(Duration d) {
  final mins = (d.inSeconds / 60).ceil();
  final up = ((mins + 4) ~/ 5) * 5;
  return Duration(minutes: up < 5 ? 5 : up);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The event is today.
bool isLeaveDay(EventDetail event, DateTime now) =>
    _day(event.parsedDate) == _day(now);

/// The event is today or later.
bool isUpcoming(EventDetail event, DateTime now) =>
    !_day(event.parsedDate).isBefore(_day(now));

/// Whether the event gets a "When to leave" row: upcoming, with a venue
/// address and a load-in or show time that hasn't passed.
bool leaveRowApplies(EventDetail event, DateTime now) {
  final venue = event.venueAddress?.trim() ?? '';
  final target = leaveTarget(event);
  return isUpcoming(event, now) &&
      venue.isNotEmpty &&
      target != null &&
      now.isBefore(target.at);
}

/// [stored] when it is offered on this event, else Home when there is a home
/// address. Null means the user still has to pick one.
LeaveStart? resolveStart(LeaveStart? stored, Set<LeaveStart> available) {
  if (stored != null && available.contains(stored)) return stored;
  if (available.contains(LeaveStart.home)) return LeaveStart.home;
  return null;
}

/// One address line from parts, skipping blanks.
String? joinAddress(List<String?> parts) {
  final kept = [
    for (final p in parts)
      if (p != null && p.trim().isNotEmpty) p.trim()
  ];
  return kept.isEmpty ? null : kept.join(', ');
}

/// What the header row and sheet show.
class LeavePlan {
  const LeavePlan({
    required this.target,
    required this.earlyBy,
    required this.available,
    this.start,
    this.hotelName,
    this.drive,
    this.leaveAt,
    this.live = false,
    this.fromHere = false,
  });

  final LeaveTarget target;
  final Duration earlyBy;

  /// Start points offered on this event.
  final Set<LeaveStart> available;
  final LeaveStart? start;

  /// This event's lodging, for the Hotel option.
  final String? hotelName;

  /// Rounded drive time; null when it couldn't be worked out.
  final Duration? drive;
  final DateTime? leaveAt;

  /// Live traffic from now (gig day), rather than typical traffic.
  final bool live;

  /// Gig day and the drive starts at the phone's location.
  final bool fromHere;

  String startLabel(LeaveStart s) =>
      s == LeaveStart.hotel ? (hotelName ?? 'Hotel') : s.label;
}

String _clock(DateTime t) => DateFormat('h:mm').format(t);

/// "35 min", or "2 h 25 min" from an hour up.
String formatDrive(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
}

/// Header row title, e.g. "Leave by ~1:55".
String leaveRowTitle(LeavePlan plan, DateTime now) {
  if (plan.start == null && !plan.fromHere) return 'Set where you leave from';
  final at = plan.leaveAt;
  if (at == null) return 'When to leave';
  if (plan.live && !at.isAfter(now)) return 'Leave now';
  return plan.live ? 'Leave by ${_clock(at)}' : 'Leave by ~${_clock(at)}';
}

/// Header row subtitle, e.g. "~35 min from home · typical Saturday traffic".
String leaveRowSubtitle(LeavePlan plan) {
  if (plan.start == null && !plan.fromHere) {
    return 'See when to leave for the ${plan.target.label}';
  }
  final drive = plan.drive;
  if (drive == null) return "Couldn't get the drive time";
  final mins = formatDrive(drive);
  if (plan.live) {
    final from = plan.fromHere ? 'here' : _fromLabel(plan);
    return '$mins in traffic now · from $from';
  }
  final day = DateFormat('EEEE').format(plan.target.at);
  return '~$mins from ${_fromLabel(plan)} · typical $day traffic';
}

String _fromLabel(LeavePlan plan) => switch (plan.start) {
      LeaveStart.home => 'home',
      LeaveStart.gearPickup => plan.available.contains(LeaveStart.home)
          ? 'home via gear pickup'
          : 'gear pickup',
      LeaveStart.hotel => plan.hotelName ?? 'the hotel',
      LeaveStart.here => 'where you are',
      null => 'here',
    };

/// The sheet's drive caption, e.g. "Typical traffic, Saturday ~2 PM".
String driveCaption(LeavePlan plan) {
  if (plan.live) return 'Live traffic now';
  final at = plan.leaveAt ?? plan.target.at;
  final hour = DateFormat('h a').format(DateTime(
      at.year, at.month, at.day, at.minute >= 30 ? at.hour + 1 : at.hour));
  return 'Typical traffic, ${DateFormat('EEEE').format(at)} ~$hour';
}

/// "Sat, Nov 7 · to make the 2:30 load-in".
String targetCaption(LeavePlan plan) =>
    '${DateFormat('EEE, MMM d').format(plan.target.at)} · to make the '
    '${_clock(plan.target.at)} ${plan.target.label}';
