import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';

import '../../helpers/test_harness.dart';

void main() {
  Dio dioReturning(Map<String, dynamic> body) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((_) async => json(200, body));
    return dio;
  }

  /// Like [dioReturning] but records every outgoing [RequestOptions] into
  /// [captured] so tests can assert on method, path, query and payload —
  /// same idiom as the band_settings repository test's lastPatchPath/Data.
  Dio dioCapturing(List<RequestOptions> captured, Map<String, dynamic> body) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        captured.add(options);
        return json(200, body);
      });
    return dio;
  }

  final threadJson = {
    'conversation': {'id': 5, 'type': 'topic', 'title': 'Gig at Blue Room'},
    'messages': [
      {
        'id': 1,
        'conversation_id': 5,
        'user_id': 2,
        'user_name': 'Eddie',
        'body': 'sound check at 6',
        'created_at': '2026-07-12T14:00:00Z',
      },
    ],
    'participants': [
      {'user_id': 2, 'name': 'Eddie', 'last_read_at': '2026-07-12T14:00:00Z'},
    ],
    'channel': 'private-conversation.5',
    'has_more': false,
  };

  final messageJson = {
    'message': {
      'id': 2,
      'conversation_id': 5,
      'user_id': 2,
      'user_name': 'Eddie',
      'body': 'hi',
      'created_at': '2026-07-12T15:00:00Z',
    },
  };

  test('listConversations parses list', () async {
    final repo = ChatRepository(dioReturning({
      'conversations': [
        {'id': 5, 'type': 'band', 'title': 'The Band', 'unread_count': 2},
      ],
    }));
    final list = await repo.listConversations();
    expect(list.single.id, 5);
    expect(list.single.unreadCount, 2);
  });

  test('openDm parses conversation', () async {
    final repo = ChatRepository(dioReturning({
      'conversation': {'id': 9, 'type': 'dm', 'title': 'Sam'},
    }));
    final c = await repo.openDm(3);
    expect(c.id, 9);
    expect(c.type, 'dm');
  });

  test('topicThread and messages parse a ThreadPage', () async {
    final repo = ChatRepository(dioReturning(threadJson));
    final page = await repo.topicThread(kind: 'events', idOrKey: 'abc123');
    expect(page.conversation.id, 5);
    expect(page.messages.single.body, 'sound check at 6');
    expect(page.participants.single.userId, 2);
    expect(page.channel, 'private-conversation.5');
    expect(page.hasMore, isFalse);

    final page2 = await repo.messages(5, beforeId: 100);
    expect(page2.conversation.id, 5);
  });

  test('topicThread GETs the events, rehearsals, and bookings paths',
      () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, threadJson));

    await repo.topicThread(kind: 'events', idOrKey: 'abc123');
    await repo.topicThread(kind: 'rehearsals', idOrKey: '12');
    await repo.topicThread(kind: 'bookings', idOrKey: '44', bandId: 3);

    expect(captured, hasLength(3));
    expect(captured.map((o) => o.method), everyElement('GET'));
    expect(captured[0].path, '/api/mobile/events/abc123/conversation');
    expect(captured[1].path, '/api/mobile/rehearsals/12/conversation');
    expect(captured[2].path, '/api/mobile/bands/3/bookings/44/conversation');
  });

  test('topicThread for bookings without bandId throws ArgumentError',
      () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, threadJson));

    await expectLater(
      repo.topicThread(kind: 'bookings', idOrKey: '44'),
      throwsArgumentError,
    );
    // Guard fires before any HTTP request is issued.
    expect(captured, isEmpty);
  });

  test('messages passes beforeId as the before query param', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, threadJson));

    await repo.messages(5, beforeId: 100);

    final req = captured.single;
    expect(req.method, 'GET');
    expect(req.path, '/api/mobile/conversations/5/messages');
    expect(req.uri.queryParameters['before'], '100');

    // Without beforeId no query param is sent.
    await repo.messages(5);
    expect(captured[1].uri.queryParameters.containsKey('before'), isFalse);
  });

  test('sendMessage and editMessage parse the message envelope', () async {
    final repo = ChatRepository(dioReturning(messageJson));
    final sent = await repo.sendMessage(5, body: 'hi');
    expect(sent.id, 2);
    final edited = await repo.editMessage(2, 'hi!');
    expect(edited.id, 2);
  });

  test('sendMessage POSTs multipart with images[] and jpeg content type',
      () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, messageJson));

    await repo.sendMessage(
      5,
      body: 'pics',
      images: const [
        ChatImageUpload(bytes: [1, 2, 3], filename: 'a.jpg'),
        ChatImageUpload(bytes: [4, 5], filename: 'b.jpg'),
      ],
    );

    final req = captured.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/mobile/conversations/5/messages');

    final form = req.data as FormData;
    final bodyField = form.fields.singleWhere((e) => e.key == 'body');
    expect(bodyField.value, 'pics');
    expect(form.files, hasLength(2));
    expect(form.files.map((e) => e.key), everyElement('images[]'));
    expect(form.files.first.value.filename, 'a.jpg');
    expect(form.files.first.value.contentType.toString(), 'image/jpeg');
  });

  test('editMessage PATCHes the message path with the body', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, messageJson));

    await repo.editMessage(2, 'hi!');

    final req = captured.single;
    expect(req.method, 'PATCH');
    expect(req.path, '/api/mobile/messages/2');
    expect(req.data, {'body': 'hi!'});
  });

  test('deleteMessage DELETEs the message path', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {}));

    await repo.deleteMessage(2);

    final req = captured.single;
    expect(req.method, 'DELETE');
    expect(req.path, '/api/mobile/messages/2');
  });

  test('markRead POSTs last_read_message_id to the read path', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {}));

    await repo.markRead(5, 10);

    final req = captured.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/mobile/conversations/5/read');
    expect(req.data, {'last_read_message_id': 10});
  });

  test('sendTyping POSTs the typing path', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {}));

    await repo.sendTyping(5);

    final req = captured.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/mobile/conversations/5/typing');
  });

  test('attachmentUrl is absolute', () {
    final repo = ChatRepository(Dio(BaseOptions(baseUrl: 'http://test.local')));
    expect(repo.attachmentUrl(2, 7),
        'http://test.local/api/mobile/messages/2/attachments/7');
  });

  test('attachmentBytes requests binary and returns the raw bytes', () async {
    final captured = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = StubAdapter((options) async {
        captured.add(options);
        return ResponseBody.fromBytes(Uint8List.fromList([1, 2, 3]), 200);
      });
    final repo = ChatRepository(dio);

    final bytes = await repo.attachmentBytes(9, 4);

    expect(bytes, [1, 2, 3]);
    expect(captured.single.path, '/api/mobile/messages/9/attachments/4');
    expect(captured.single.responseType, ResponseType.bytes);
  });

  test('addReaction posts emoji and parses reactions', () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {
      'reactions': [
        {'emoji': '👍', 'count': 1, 'user_ids': [2]},
      ],
    }));

    final reactions = await repo.addReaction(9, '👍');

    expect(captured.single.method, 'POST');
    expect(captured.single.path, '/api/mobile/messages/9/reactions');
    expect(captured.single.data, {'emoji': '👍'});
    expect(reactions.single.emoji, '👍');
    expect(reactions.single.userIds, [2]);
  });

  test('removeReaction deletes percent-encoded emoji and parses reactions',
      () async {
    final captured = <RequestOptions>[];
    final repo = ChatRepository(dioCapturing(captured, {'reactions': []}));

    final reactions = await repo.removeReaction(9, '👍');

    expect(captured.single.method, 'DELETE');
    expect(captured.single.path,
        '/api/mobile/messages/9/reactions/${Uri.encodeComponent('👍')}');
    expect(reactions, isEmpty);
  });
}
