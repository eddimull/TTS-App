import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/leave_plan.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';

EventDetail _event({
  String date = '2026-11-07',
  String? time = '16:30',
  String? address = '1911 Magazine St, New Orleans',
  List<Map<String, dynamic>> timeline = const [
    {'title': 'Load in', 'time': '2026-11-07 14:30'},
  ],
}) =>
    EventDetail.fromJson({
      'id': 1,
      'key': 'k',
      'title': 'Gig',
      'date': date,
      'time': time,
      'venue_name': 'Il Mercato',
      'venue_address': address,
      'can_write': true,
      'members': <dynamic>[],
      'timeline': timeline,
    });

LeavePlan _plan({
  LeaveStart? start = LeaveStart.home,
  Duration? drive = const Duration(minutes: 35),
  bool live = false,
  bool fromHere = false,
  Set<LeaveStart> available = const {LeaveStart.home, LeaveStart.gearPickup},
}) {
  final target =
      LeaveTarget(label: 'load-in', at: DateTime(2026, 11, 7, 14, 30));
  return LeavePlan(
    target: target,
    earlyBy: defaultEarlyBy,
    available: available,
    start: start,
    drive: drive,
    leaveAt: drive == null
        ? null
        : leaveBy(arriveBy: target.at, earlyBy: defaultEarlyBy, drive: drive),
    live: live,
    fromHere: fromHere,
  );
}

void main() {
  group('leaveTarget', () {
    test('prefers load-in', () {
      final t = leaveTarget(_event())!;
      expect(t.label, 'load-in');
      expect(t.at, DateTime(2026, 11, 7, 14, 30));
    });

    test('falls back to the show, a bare time on the event date', () {
      final t = leaveTarget(_event(timeline: const []))!;
      expect(t.label, 'show');
      expect(t.at, DateTime(2026, 11, 7, 16, 30));
    });

    test('a bare load-in time lands on the event date', () {
      final t = leaveTarget(_event(timeline: const [
        {'title': 'Load-in', 'time': '15:00'},
      ]))!;
      expect(t.at, DateTime(2026, 11, 7, 15, 0));
    });

    test('a timeline date from another year is ignored', () {
      final t = leaveTarget(_event(timeline: const [
        {'title': 'Load In', 'time': '2025-11-07 15:30:00'},
      ]))!;
      expect(t.at, DateTime(2026, 11, 7, 15, 30));
    });

    test('null without any time', () {
      expect(leaveTarget(_event(time: null, timeline: const [])), isNull);
    });
  });

  group('leaveBy', () {
    test('subtracts early-by and drive, rounded down to 5 min', () {
      expect(
        leaveBy(
          arriveBy: DateTime(2026, 11, 7, 14, 30),
          earlyBy: const Duration(minutes: 10),
          drive: const Duration(minutes: 33),
        ),
        DateTime(2026, 11, 7, 13, 45),
      );
    });

    test('exact five-minute results stay put', () {
      expect(
        leaveBy(
          arriveBy: DateTime(2026, 11, 7, 14, 30),
          earlyBy: const Duration(minutes: 10),
          drive: const Duration(minutes: 35),
        ),
        DateTime(2026, 11, 7, 13, 45),
      );
    });

    test('crosses midnight', () {
      expect(
        leaveBy(
          arriveBy: DateTime(2026, 11, 7, 0, 20),
          earlyBy: Duration.zero,
          drive: const Duration(minutes: 30),
        ),
        DateTime(2026, 11, 6, 23, 50),
      );
    });
  });

  test('roundDrive rounds up to 5 min, at least 5', () {
    expect(
        roundDrive(const Duration(minutes: 31)), const Duration(minutes: 35));
    expect(
        roundDrive(const Duration(minutes: 35)), const Duration(minutes: 35));
    expect(
        roundDrive(const Duration(seconds: 2101)), const Duration(minutes: 40));
    expect(roundDrive(const Duration(seconds: 40)), const Duration(minutes: 5));
  });

  test('formatDrive shows hours from an hour up', () {
    expect(formatDrive(const Duration(minutes: 35)), '35 min');
    expect(formatDrive(const Duration(minutes: 60)), '1 h');
    expect(formatDrive(const Duration(minutes: 145)), '2 h 25 min');
  });

  group('leaveRowApplies', () {
    final before = DateTime(2026, 11, 1, 9);
    test('upcoming event with an address and a time', () {
      expect(leaveRowApplies(_event(), before), isTrue);
    });
    test('not for past events', () {
      expect(leaveRowApplies(_event(), DateTime(2026, 11, 8)), isFalse);
    });
    test('not once the load-in has passed', () {
      expect(leaveRowApplies(_event(), DateTime(2026, 11, 7, 14, 31)), isFalse);
      expect(leaveRowApplies(_event(), DateTime(2026, 11, 7, 14, 29)), isTrue);
    });
    test('not without a venue address', () {
      expect(leaveRowApplies(_event(address: null), before), isFalse);
      expect(leaveRowApplies(_event(address: '  '), before), isFalse);
    });
  });

  group('resolveStart', () {
    const all = {LeaveStart.home, LeaveStart.gearPickup, LeaveStart.here};
    test('keeps the stored choice when offered', () {
      expect(resolveStart(LeaveStart.gearPickup, all), LeaveStart.gearPickup);
    });
    test('hotel stored but no lodging on this event falls back to home', () {
      expect(resolveStart(LeaveStart.hotel, all), LeaveStart.home);
    });
    test('nothing stored and no home address means not set', () {
      expect(resolveStart(null, const {LeaveStart.here}), isNull);
    });
  });

  test('joinAddress skips blanks', () {
    expect(joinAddress(['1 Main St', null, ' ', 'New Orleans', '70115']),
        '1 Main St, New Orleans, 70115');
    expect(joinAddress([null, '']), isNull);
  });

  group('row text', () {
    final now = DateTime(2026, 11, 1, 9);
    test('typical traffic from home', () {
      final p = _plan();
      expect(leaveRowTitle(p, now), 'Leave by ~1:45');
      expect(
          leaveRowSubtitle(p), '~35 min from home · typical Saturday traffic');
    });

    test('gear pickup from home', () {
      expect(leaveRowSubtitle(_plan(start: LeaveStart.gearPickup)),
          '~35 min from home via gear pickup · typical Saturday traffic');
      expect(
          leaveRowSubtitle(_plan(
              start: LeaveStart.gearPickup,
              available: const {LeaveStart.gearPickup})),
          '~35 min from gear pickup · typical Saturday traffic');
    });

    test('no start point yet', () {
      final p = _plan(start: null, drive: null);
      expect(leaveRowTitle(p, now), 'Set where you leave from');
      expect(leaveRowSubtitle(p), 'See when to leave for the load-in');
    });

    test('drive time failed', () {
      final p = _plan(drive: null);
      expect(leaveRowTitle(p, now), 'When to leave');
      expect(leaveRowSubtitle(p), "Couldn't get the drive time");
    });

    test('gig day, live traffic from here', () {
      final p = _plan(
          start: null,
          drive: const Duration(minutes: 30),
          live: true,
          fromHere: true);
      expect(leaveRowTitle(p, DateTime(2026, 11, 7, 12)), 'Leave by 1:50');
      expect(leaveRowSubtitle(p), '30 min in traffic now · from here');
      expect(leaveRowTitle(p, DateTime(2026, 11, 7, 13, 55)), 'Leave now');
    });

    test('sheet captions', () {
      final p = _plan();
      expect(targetCaption(p), 'Sat, Nov 7 · to make the 2:30 load-in');
      expect(driveCaption(p), 'Typical traffic, Saturday ~2 PM');
      expect(driveCaption(_plan(live: true)), 'Live traffic now');
    });
  });
}
