import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_message.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/rehearsal_planner_repository.dart';
import 'package:tts_bandmate/features/rehearsal_planner/providers/rehearsal_planner_provider.dart';

class FakeRepo implements RehearsalPlannerRepository {
  @override
  Future<({int sessionId, String channel, int assistantMessageId})> startSession(
          int bandId) async =>
      (sessionId: 1, channel: 'private-rehearsal-planner.1', assistantMessageId: 100);

  @override
  Future<({PlannerMessage userMessage, int assistantMessageId, String channel})>
      sendMessage(int bandId, int sessionId, String text) async => (
            userMessage:
                PlannerMessage(id: 200, role: 'user', text: text, status: 'complete'),
            assistantMessageId: 201,
            channel: 'private-rehearsal-planner.1',
          );

  @override
  Future<List<PlannerMessage>> history(int bandId, int sessionId) async => [];
}

void main() {
  late void Function(String, Map<String, dynamic>)? onEvent;

  ProviderContainer makeContainer() {
    onEvent = null;
    return ProviderContainer(overrides: [
      rehearsalPlannerRepositoryProvider.overrideWithValue(FakeRepo()),
      plannerStreamBinderProvider
          .overrideWithValue((channel, cb) => onEvent = cb),
    ]);
  }

  test('start inserts streaming placeholder and binds channel', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(7).notifier).start();

    final s = c.read(rehearsalPlannerProvider(7));
    expect(s.sessionId, 1);
    expect(s.messages.single.status, 'streaming');
    expect(onEvent, isNotNull); // channel bound
  });

  test('text_delta appends to streaming message; done finalizes', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(7).notifier).start();

    onEvent!('text_delta', {'delta': 'Hel'});
    onEvent!('text_delta', {'delta': 'lo'});
    expect(c.read(rehearsalPlannerProvider(7)).messages.single.text, 'Hello');

    onEvent!('done', {
      'message_id': 100,
      'content': 'Hello there',
      'suggestions': ['A', 'B'],
      'plan': null,
    });
    final m = c.read(rehearsalPlannerProvider(7)).messages.single;
    expect(m.status, 'complete');
    expect(m.text, 'Hello there');
    expect(m.suggestions, ['A', 'B']);
  });

  test('done with empty content keeps already-accumulated streamed text', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(7).notifier).start();

    onEvent!('text_delta', {'delta': 'Hello'});
    expect(c.read(rehearsalPlannerProvider(7)).messages.single.text, 'Hello');

    // Backend sends done with empty content (fenced blocks only → stripped to '').
    onEvent!('done', {
      'message_id': 100,
      'content': '',
      'suggestions': ['Follow-up'],
      'plan': null,
    });
    final m = c.read(rehearsalPlannerProvider(7)).messages.single;
    // Streamed text must NOT be wiped.
    expect(m.text, 'Hello');
    expect(m.status, 'complete');
    expect(m.suggestions, ['Follow-up']);
  });

  test('text_delta with message_id appends to that specific message, not the last one',
      () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(7).notifier);

    // Start creates streaming placeholder id=100.
    await n.start();

    // Mark the first placeholder as complete so it's no longer the "last streaming".
    onEvent!('done', {
      'message_id': 100,
      'content': 'First reply',
      'suggestions': [],
      'plan': null,
    });

    // Send a message → adds user msg (id=200) + new streaming placeholder (id=201).
    await n.send('follow-up');

    // Now two messages: id=100 (complete) and id=201 (streaming).
    // Fire a text_delta targeting the *first* message by id — it is not the last
    // streaming message, so the fallback path would hit the wrong one.
    onEvent!('text_delta', {'message_id': 100, 'delta': '-extra'});

    final msgs = c.read(rehearsalPlannerProvider(7)).messages;
    // id=100 should have grown; id=201 (streaming placeholder) should stay empty.
    final first = msgs.firstWhere((m) => m.id == 100);
    final second = msgs.firstWhere((m) => m.id == 201);
    expect(first.text, 'First reply-extra');
    expect(second.text, '');
  });

  test('error marks message failed; retryLast re-sends prior user text', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(7).notifier);
    await n.start();
    onEvent!('done',
        {'message_id': 100, 'content': 'opening', 'suggestions': [], 'plan': null});

    await n.send('plan please');
    onEvent!('error', {'message_id': 201});
    expect(c.read(rehearsalPlannerProvider(7)).messages.last.status, 'failed');

    await n.retryLast();
    // After retry, a new streaming placeholder exists (id 201 again from fake).
    expect(c.read(rehearsalPlannerProvider(7)).messages.last.status, 'streaming');
  });
}
