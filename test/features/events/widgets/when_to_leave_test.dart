import 'package:clock/clock.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/features/events/data/leave_plan.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/providers/leave_plan_provider.dart';
import 'package:tts_bandmate/features/events/widgets/when_to_leave.dart';

const _key = 'evt';

final _event = EventDetail.fromJson({
  'id': 1,
  'key': _key,
  'title': 'Gig',
  'date': '2026-11-07',
  'time': '16:30',
  'venue_name': 'Il Mercato',
  'venue_address': '1911 Magazine St',
  'can_write': true,
  'members': <dynamic>[],
  'timeline': [
    {'title': 'Load in', 'time': '2026-11-07 14:30'},
  ],
});

LeavePlan _plan(LeaveSettings s) {
  final target =
      LeaveTarget(label: 'load-in', at: DateTime(2026, 11, 7, 14, 30));
  const drive = Duration(minutes: 35);
  return LeavePlan(
    target: target,
    earlyBy: s.earlyBy,
    available: const {
      LeaveStart.home,
      LeaveStart.gearPickup,
      LeaveStart.here,
    },
    start: s.start ?? LeaveStart.home,
    drive: drive,
    leaveAt: leaveBy(arriveBy: target.at, earlyBy: s.earlyBy, drive: drive),
  );
}

Future<void> _pump(WidgetTester tester, {bool enabled = true}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      leaveTimesEnabledProvider.overrideWithValue(enabled),
      leavePlanProvider.overrideWith((ref, key) async =>
          _plan(await ref.watch(leaveSettingsProvider.future))),
    ],
    child: CupertinoApp(
      home: CupertinoPageScaffold(
        child: Center(child: LeaveByRow(event: _event)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header row shows the leave time and drive', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 1, 9)), () async {
      await _pump(tester);
      expect(find.text('Leave by ~1:45'), findsOneWidget);
      expect(find.text('~35 min from home · typical Saturday traffic'),
          findsOneWidget);
    });
  });

  testWidgets('hidden when leave times are off', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 1, 9)), () async {
      await _pump(tester, enabled: false);
      expect(find.textContaining('Leave by'), findsNothing);
    });
  });

  testWidgets('sheet changes the start point and early-by on the phone',
      (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 1, 9)), () async {
      await _pump(tester);
      await tester.tap(find.text('Leave by ~1:45'));
      await tester.pumpAndSettle();

      expect(find.text('When to leave'), findsOneWidget);
      expect(find.text('~1:45 PM'), findsOneWidget);
      expect(
          find.text('Sat, Nov 7 · to make the 2:30 load-in'), findsOneWidget);
      expect(find.text('Hotel'), findsNothing);

      await tester.tap(find.text('Gear pickup'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(leaveStartKey), 'gearPickup');
      expect(
          find.text(
              '~35 min from home via gear pickup · typical Saturday traffic'),
          findsOneWidget);

      await tester.tap(find.text('10 min ›'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();
      expect(prefs.getInt(leaveEarlyByKey), 20);
      expect(find.text('~1:35 PM'), findsOneWidget);
    });
  });

  testWidgets('gig day buttons go live', (tester) async {
    var live = 0;
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: Center(
          child: GigDayActions(event: _event, onGoLive: () => live++),
        ),
      ),
    ));
    expect(find.text('Directions'), findsOneWidget);
    await tester.tap(find.text('Go live'));
    expect(live, 1);
  });

  testWidgets('read-only members get Directions but no Go live',
      (tester) async {
    final readOnly = EventDetail.fromJson({
      'id': 1,
      'key': _key,
      'title': 'Gig',
      'date': '2026-11-07',
      'venue_name': 'Il Mercato',
      'can_write': false,
      'members': <dynamic>[],
    });
    await tester.pumpWidget(CupertinoApp(
      home: CupertinoPageScaffold(
        child: Center(child: GigDayActions(event: readOnly, onGoLive: () {})),
      ),
    ));
    expect(find.text('Directions'), findsOneWidget);
    expect(find.text('Go live'), findsNothing);
  });
}
