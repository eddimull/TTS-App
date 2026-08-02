import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/data/models/conversation.dart';
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_detail.dart';
import 'package:tts_bandmate/features/rehearsals/data/models/rehearsal_sub.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';
import 'package:tts_bandmate/features/rehearsals/screens/rehearsal_detail_screen.dart';

class _FakeRehearsalsRepository extends RehearsalsRepository {
  _FakeRehearsalsRepository() : super(Dio());
}

// The embedded CommentBar resolves its topic thread via a provider; stub
// it so the section renders instantly without a network call in these tests.
ThreadPage _emptyThread() => (
      conversation: const Conversation(id: 999, type: 'topic', title: ''),
      messages: const [],
      participants: const [],
      channel: '',
      hasMore: false,
    );

Widget _app(_FakeRehearsalsRepository repo, RehearsalDetail preloaded) {
  return ProviderScope(
    overrides: [
      rehearsalsRepositoryProvider.overrideWithValue(repo),
      topicThreadProvider.overrideWith((ref, topic) => _emptyThread()),
    ],
    child: CupertinoApp(home: RehearsalDetailScreen(preloaded: preloaded)),
  );
}

void main() {
  testWidgets('renders invited subs with role badges', (tester) async {
    final repo = _FakeRehearsalsRepository();
    const detail = RehearsalDetail(
      id: 1,
      isCancelled: false,
      schedule: ScheduleStub(id: 2, name: 'Weekly'),
      associatedBookings: [],
      subs: [
        RehearsalSub(id: 5, name: 'Pat Horn', roleName: 'Trumpet'),
        RehearsalSub(id: 6, name: 'Ad Hoc'),
      ],
    );

    await tester.pumpWidget(_app(repo, detail));
    await tester.pumpAndSettle();

    expect(find.text('Subs'), findsOneWidget);
    expect(find.text('Pat Horn'), findsOneWidget);
    expect(find.text('Trumpet'), findsOneWidget);
    expect(find.text('Ad Hoc'), findsOneWidget);
  });

  testWidgets('shows empty state when no subs', (tester) async {
    final repo = _FakeRehearsalsRepository();
    const detail = RehearsalDetail(
      id: 1,
      isCancelled: false,
      schedule: ScheduleStub(id: 2, name: 'Weekly'),
      associatedBookings: [],
      subs: [],
    );

    await tester.pumpWidget(_app(repo, detail));
    await tester.pumpAndSettle();

    expect(find.text('No subs invited.'), findsOneWidget);
  });
}
