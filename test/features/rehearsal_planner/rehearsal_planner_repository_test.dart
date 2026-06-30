import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsal_planner/data/rehearsal_planner_repository.dart';

import '../../helpers/test_harness.dart';

void main() {
  Dio dioReturning(Map<String, dynamic> body) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, body));
    return dio;
  }

  test('startSession parses ids and channel', () async {
    final repo = RehearsalPlannerRepository(dioReturning({
      'session_id': 9,
      'channel': 'private-rehearsal-planner.9',
      'assistant_message_id': 21,
    }));
    final r = await repo.startSession(3);
    expect(r.sessionId, 9);
    expect(r.channel, 'private-rehearsal-planner.9');
    expect(r.assistantMessageId, 21);
  });

  test('sendMessage parses user message and channel', () async {
    final repo = RehearsalPlannerRepository(dioReturning({
      'user_message': {
        'id': 50,
        'role': 'user',
        'content': 'hi',
        'status': 'complete',
      },
      'assistant_message_id': 51,
      'channel': 'private-rehearsal-planner.9',
    }));
    final r = await repo.sendMessage(3, 9, 'hi');
    expect(r.userMessage.text, 'hi');
    expect(r.assistantMessageId, 51);
  });

  test('history parses messages list into List<PlannerMessage>', () async {
    final repo = RehearsalPlannerRepository(dioReturning({
      'messages': [
        {'id': 1, 'role': 'user', 'content': 'hello', 'status': 'complete'},
        {
          'id': 2,
          'role': 'assistant',
          'content': 'Hi there!',
          'status': 'complete',
        },
      ],
    }));
    final messages = await repo.history(3, 9);
    expect(messages.length, 2);
    expect(messages[0].text, 'hello');
    expect(messages[0].role, 'user');
    expect(messages[1].text, 'Hi there!');
    expect(messages[1].role, 'assistant');
  });
}
