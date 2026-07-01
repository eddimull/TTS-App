import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_message.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/models/planner_plan.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/rehearsal_planner_repository.dart';
import 'package:tts_bandmate/features/rehearsal_planner/providers/rehearsal_planner_provider.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';

class FakeRehearsalsRepo extends RehearsalsRepository {
  FakeRehearsalsRepo() : super(Dio());

  int? lastRehearsalId;
  String? lastNotes;
  bool shouldThrow = false;

  @override
  Future<String?> updateNotes(int rehearsalId, String? notes) async {
    if (shouldThrow) throw Exception('network');
    lastRehearsalId = rehearsalId;
    lastNotes = notes;
    return notes;
  }
}

class FakeRepo implements RehearsalPlannerRepository {
  @override
  Future<({int sessionId, String channel, int assistantMessageId})> startSession(
          int bandId, {int? rehearsalId}) async =>
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
  const args = PlannerArgs(bandId: 7, rehearsalId: 1);
  late FakeRehearsalsRepo rehearsalsRepo;

  ProviderContainer makeContainer() {
    onEvent = null;
    rehearsalsRepo = FakeRehearsalsRepo();
    return ProviderContainer(overrides: [
      rehearsalPlannerRepositoryProvider.overrideWithValue(FakeRepo()),
      rehearsalsRepositoryProvider.overrideWithValue(rehearsalsRepo),
      // The real plannerStreamBinderProvider closure (the Pusher-facing one) is
      // intentionally NOT exercised here — it's replaced by this fake. That
      // closure's correctness is an AOT-only concern (see BANDMATE-APP-P:
      // contravariant onEvent param type) that `flutter test` runs in JIT and
      // therefore cannot catch; `flutter analyze` + a release build are the
      // real guards. These tests cover the notifier's event-handling instead.
      plannerStreamBinderProvider
          .overrideWithValue((channel, cb) => onEvent = cb),
    ]);
  }

  test('start inserts streaming placeholder and binds channel', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(args).notifier).start();

    final s = c.read(rehearsalPlannerProvider(args));
    expect(s.sessionId, 1);
    expect(s.messages.single.status, 'streaming');
    expect(onEvent, isNotNull); // channel bound
  });

  test('text_delta appends to streaming message; done finalizes', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(args).notifier).start();

    onEvent!('text_delta', {'delta': 'Hel'});
    onEvent!('text_delta', {'delta': 'lo'});
    expect(c.read(rehearsalPlannerProvider(args)).messages.single.text, 'Hello');

    onEvent!('done', {
      'message_id': 100,
      'content': 'Hello there',
      'suggestions': ['A', 'B'],
      'plan': null,
    });
    final m = c.read(rehearsalPlannerProvider(args)).messages.single;
    expect(m.status, 'complete');
    expect(m.text, 'Hello there');
    expect(m.suggestions, ['A', 'B']);
  });

  test('done with empty content keeps already-accumulated streamed text', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    await c.read(rehearsalPlannerProvider(args).notifier).start();

    onEvent!('text_delta', {'delta': 'Hello'});
    expect(c.read(rehearsalPlannerProvider(args)).messages.single.text, 'Hello');

    // Backend sends done with empty content (fenced blocks only → stripped to '').
    onEvent!('done', {
      'message_id': 100,
      'content': '',
      'suggestions': ['Follow-up'],
      'plan': null,
    });
    final m = c.read(rehearsalPlannerProvider(args)).messages.single;
    // Streamed text must NOT be wiped.
    expect(m.text, 'Hello');
    expect(m.status, 'complete');
    expect(m.suggestions, ['Follow-up']);
  });

  test('text_delta with message_id appends to that specific message, not the last one',
      () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);

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

    final msgs = c.read(rehearsalPlannerProvider(args)).messages;
    // id=100 should have grown; id=201 (streaming placeholder) should stay empty.
    final first = msgs.firstWhere((m) => m.id == 100);
    final second = msgs.firstWhere((m) => m.id == 201);
    expect(first.text, 'First reply-extra');
    expect(second.text, '');
  });

  test('error marks message failed; retryLast re-sends prior user text', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);
    await n.start();
    onEvent!('done',
        {'message_id': 100, 'content': 'opening', 'suggestions': [], 'plan': null});

    await n.send('plan please');
    onEvent!('error', {'message_id': 201});
    expect(c.read(rehearsalPlannerProvider(args)).messages.last.status, 'failed');

    await n.retryLast();
    // After retry, a new streaming placeholder exists (id 201 again from fake).
    expect(c.read(rehearsalPlannerProvider(args)).messages.last.status, 'streaming');
  });

  const samplePlan = PlannerPlan(
    title: 'Plan',
    items: [PlannerPlanItem(title: 'Song A', reason: 'because')],
  );

  test('savePlanToNotes(replace) writes formatted plan to the rehearsal id', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    final ok = await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.replace);

    expect(ok, isTrue);
    expect(rehearsalsRepo.lastRehearsalId, 1); // args.rehearsalId
    expect(rehearsalsRepo.lastNotes, 'Plan\n\n• Song A — because');
    expect(c.read(rehearsalPlannerProvider(args)).isSavingPlan, isFalse);
  });

  test('savePlanToNotes(append) prepends existing notes with a blank line', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    final ok = await n.savePlanToNotes(
      samplePlan,
      mode: NotesSaveMode.append,
      existingNotes: 'Old notes',
    );

    expect(ok, isTrue);
    expect(rehearsalsRepo.lastNotes, 'Old notes\n\nPlan\n\n• Song A — because');
  });

  test('savePlanToNotes(append) with empty existing behaves like replace', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.append, existingNotes: '');

    expect(rehearsalsRepo.lastNotes, 'Plan\n\n• Song A — because');
  });

  test('savePlanToNotes returns false and sets error when the repo throws', () async {
    final c = makeContainer();
    addTearDown(c.dispose);
    rehearsalsRepo.shouldThrow = true;
    final n = c.read(rehearsalPlannerProvider(args).notifier);

    final ok = await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.replace);

    expect(ok, isFalse);
    expect(c.read(rehearsalPlannerProvider(args)).error, isNotNull);
    expect(c.read(rehearsalPlannerProvider(args)).isSavingPlan, isFalse);
  });

  test('savePlanToNotes returns false without calling repo when rehearsalId is null', () async {
    const noRehearsalArgs = PlannerArgs(bandId: 7); // rehearsalId null
    final c = makeContainer();
    addTearDown(c.dispose);
    final n = c.read(rehearsalPlannerProvider(noRehearsalArgs).notifier);

    final ok = await n.savePlanToNotes(samplePlan, mode: NotesSaveMode.replace);

    expect(ok, isFalse);
    expect(rehearsalsRepo.lastRehearsalId, isNull); // never called
  });
}
