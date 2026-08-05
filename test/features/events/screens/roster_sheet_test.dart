import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';
import 'package:tts_bandmate/features/dashboard/data/models/upcoming_chart.dart';
import 'package:tts_bandmate/features/events/data/events_repository.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/data/models/event_member.dart';
import 'package:tts_bandmate/features/events/data/models/event_summary.dart';
import 'package:tts_bandmate/features/events/data/models/sub_entry.dart';
import 'package:tts_bandmate/features/events/screens/roster_sheet.dart';

final _throwingDio = Dio();
const _eventKey = 'evt-key';

EventDetail _event({required String memberName, required bool isFilled}) {
  return EventDetail(
    id: 1,
    key: _eventKey,
    title: 'Summer Gala',
    date: '2026-05-20',
    canWrite: true,
    members: [
      EventMember(
        id: isFilled ? 10 : null,
        name: memberName,
        bandRoleId: 5,
        slotId: 100,
        sectionName: 'Rhythm',
        isFilled: isFilled,
      ),
    ],
    timeline: const [],
    contacts: const [],
    attachments: const [],
  );
}

/// getEventDetail returns whatever [current] points to at call time — lets a
/// test simulate the server-side state changing between calls (e.g. after an
/// assignSub mutation), the same way a real refetch would pick up new data.
class _FakeEventsRepository extends EventsRepository {
  _FakeEventsRepository(this.current) : super(_throwingDio);

  EventDetail current;
  int assignSubCalls = 0;

  @override
  Future<EventDetail> getEventDetail(String key) async => current;

  @override
  Future<List<SubEntry>> fetchSubs(String eventKey, int bandRoleId) async => [
        const SubEntry(id: 1, name: 'Jamie Sub', bandRoleId: 5, rosterMemberId: 77),
      ];

  @override
  Future<void> assignSub(
    String eventKey,
    int memberId, {
    int? slotId,
    int? rosterMemberId,
    String? name,
    String? email,
    bool clear = false,
  }) async {
    assignSubCalls++;
    // Simulate the server persisting the assignment — the next
    // getEventDetail call (triggered by the invalidation below) returns the
    // now-filled member.
    current = _event(memberName: 'Jamie Sub', isFilled: true);
  }
}

class _FakeDashboardRepository extends DashboardRepository {
  _FakeDashboardRepository() : super(_throwingDio);

  @override
  Future<({List<EventSummary> events, List<UpcomingChart> upcomingCharts})>
      getDashboard({String? to}) async =>
          (events: const <EventSummary>[], upcomingCharts: const <UpcomingChart>[]);
}

void main() {
  testWidgets(
      'sub assignment refreshes the open sheet live — no stale member list '
      'until popped and reopened', (tester) async {
    final initialEvent = _event(memberName: '', isFilled: false);
    final repo = _FakeEventsRepository(initialEvent);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventsRepositoryProvider.overrideWithValue(repo),
        dashboardRepositoryProvider.overrideWithValue(_FakeDashboardRepository()),
        // No fixed-value override here — eventDetailProvider must read
        // through the fake repo on every (re)fetch so an invalidation after
        // assignSub picks up repo.current's post-mutation state, the same
        // way the real provider re-hits the network.
      ],
      child: CupertinoApp(home: RosterSheet(event: initialEvent)),
    ));
    await tester.pumpAndSettle();

    // Unfilled slot renders the "Needed" placeholder.
    expect(find.text('— Needed'), findsOneWidget);
    expect(find.text('Jamie Sub'), findsNothing);

    // Tap the unfilled slot to open the sub picker, then tap the sub.
    await tester.tap(find.text('— Needed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jamie Sub'));
    await tester.pumpAndSettle();

    expect(repo.assignSubCalls, 1);

    // The sheet itself (never popped) must now show the assigned sub — not
    // the stale "— Needed" row — proving it watches eventDetailProvider
    // instead of the frozen widget.event snapshot.
    expect(find.text('— Needed'), findsNothing);
    expect(find.text('Jamie Sub'), findsOneWidget);
  });

  testWidgets(
      'falls back to widget.event while eventDetailProvider has not resolved',
      (tester) async {
    final event = _event(memberName: 'Original Name', isFilled: true);
    final repo = _FakeEventsRepository(event);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        eventsRepositoryProvider.overrideWithValue(repo),
        dashboardRepositoryProvider.overrideWithValue(_FakeDashboardRepository()),
        // No eventDetailProvider override — it resolves via the real
        // provider (against the fake repo), so the first frame renders
        // widget.event directly via the fallback before the future settles.
      ],
      child: CupertinoApp(home: RosterSheet(event: event)),
    ));

    // Before pumpAndSettle, the provider's future hasn't resolved yet — the
    // fallback (`?? widget.event`) must still render something sane rather
    // than a blank/loading screen.
    await tester.pump();
    expect(find.text('Original Name'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Original Name'), findsOneWidget);
  });
}
