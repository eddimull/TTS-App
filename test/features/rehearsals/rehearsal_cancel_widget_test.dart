import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_detail.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';
import 'package:tts_bandmate/features/rehearsals/screens/rehearsal_detail_screen.dart';

class _FakeRehearsalsRepository extends RehearsalsRepository {
  _FakeRehearsalsRepository() : super(Dio());

  final calls = <(int, bool)>[];

  @override
  Future<RehearsalDetail> setCancelled(int rehearsalId, bool isCancelled) async {
    calls.add((rehearsalId, isCancelled));
    return _detail(isCancelled: isCancelled);
  }
}

RehearsalDetail _detail({bool isCancelled = false}) {
  final future = DateTime.now().add(const Duration(days: 7));
  final date =
      '${future.year}-${future.month.toString().padLeft(2, '0')}-${future.day.toString().padLeft(2, '0')}';
  return RehearsalDetail.fromJson({
    'id': 42,
    'date': date,
    'time': '19:00',
    'venue_name': 'The Shed',
    'is_cancelled': isCancelled,
    'notes': null,
    'event_key': 'k-1',
    'schedule': {'id': 7, 'name': 'Tuesday Practice', 'location_name': 'The Shed'},
    'associated_bookings': [],
  });
}

Widget _app(_FakeRehearsalsRepository repo, RehearsalDetail preloaded) {
  return ProviderScope(
    overrides: [rehearsalsRepositoryProvider.overrideWithValue(repo)],
    child: CupertinoApp(home: RehearsalDetailScreen(preloaded: preloaded)),
  );
}

void main() {
  testWidgets('upcoming rehearsal shows cancel button; confirming calls repo', (tester) async {
    final repo = _FakeRehearsalsRepository();
    await tester.pumpWidget(_app(repo, _detail()));

    expect(find.text('Cancel Rehearsal'), findsOneWidget);

    await tester.tap(find.text('Cancel Rehearsal'));
    await tester.pumpAndSettle();

    // Action sheet with a destructive confirm.
    expect(find.text('Cancel this rehearsal?'), findsOneWidget);
    await tester.tap(find.text('Cancel Rehearsal').last);
    await tester.pumpAndSettle();

    expect(repo.calls, [(42, true)]);
    // UI flipped to cancelled state.
    expect(find.text('This rehearsal has been cancelled.'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
  });

  testWidgets('cancelled rehearsal shows restore; confirming calls repo', (tester) async {
    final repo = _FakeRehearsalsRepository();
    await tester.pumpWidget(_app(repo, _detail(isCancelled: true)));

    expect(find.text('Cancel Rehearsal'), findsNothing);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Restore this rehearsal?'), findsOneWidget);
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();

    expect(repo.calls, [(42, false)]);
    expect(find.text('This rehearsal has been cancelled.'), findsNothing);
  });

  testWidgets('past rehearsal shows no cancel button', (tester) async {
    final repo = _FakeRehearsalsRepository();
    final past = RehearsalDetail.fromJson({
      'id': 42,
      'date': '2020-01-01',
      'time': '19:00',
      'venue_name': 'The Shed',
      'is_cancelled': false,
      'notes': null,
      'event_key': 'k-1',
      'schedule': {'id': 7, 'name': 'Tuesday Practice', 'location_name': 'The Shed'},
      'associated_bookings': [],
    });
    await tester.pumpWidget(_app(repo, past));

    expect(find.text('Cancel Rehearsal'), findsNothing);
  });
}
