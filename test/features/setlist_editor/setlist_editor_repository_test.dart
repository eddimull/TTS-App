import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/setlist_editor/data/models/event_setlist.dart';
import 'package:tts_bandmate/features/setlist_editor/data/setlist_editor_repository.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final Future<ResponseBody> Function(RequestOptions) responder;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, __) => responder(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio();
  });

  test('getSetlist parses payload', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/events/abc/setlist');
      expect(req.method, 'GET');
      return _json(200, {
        'event': {'id': 1, 'key': 'abc', 'title': 'Show'},
        'setlist': {
          'id': 1,
          'status': 'draft',
          'songs': [
            {'id': 1, 'type': 'song', 'position': 1, 'title': 'Song A'}
          ],
        },
        'songs': [
          {'id': 10, 'title': 'A'},
        ],
        'can_write': true,
      });
    });

    final repo = SetlistEditorRepository(dio);
    final result = await repo.getSetlist('abc');

    expect(result.setlist?.songs.length, 1);
    expect(result.bandSongs.first.title, 'A');
    expect(result.canWrite, true);
  });

  test('getSetlist handles null setlist', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      return _json(200, {
        'event': {'id': 1, 'key': 'abc', 'title': 'Show'},
        'setlist': null,
        'songs': [],
        'can_write': false,
      });
    });

    final repo = SetlistEditorRepository(dio);
    final result = await repo.getSetlist('abc');

    expect(result.setlist, isNull);
    expect(result.bandSongs, isEmpty);
    expect(result.canWrite, false);
  });

  test('updateSetlist serialises entries correctly', () async {
    Map<String, dynamic>? capturedBody;

    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      expect(req.method, 'PUT');
      expect(req.path, '/api/mobile/events/abc/setlist');
      return _json(200, {
        'id': 1,
        'status': 'ready',
        'songs': [],
      });
    });

    final repo = SetlistEditorRepository(dio);
    final result = await repo.updateSetlist('abc', [
      const SetlistEntry(type: 'song', position: 1, songId: 5),
      const SetlistEntry(type: 'break', position: 2),
    ], status: 'ready');

    expect(capturedBody!['status'], 'ready');
    expect((capturedBody!['songs'] as List).length, 2);
    expect((capturedBody!['songs'] as List).first['song_id'], 5);
    // Position is derived server-side from array index — must NOT be sent.
    expect(
      (capturedBody!['songs'] as List).first.containsKey('position'),
      isFalse,
    );
    expect(result.status, 'ready');
  });

  test('generate posts context and parses the bare setlist', () async {
    Map<String, dynamic>? capturedBody;

    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      expect(req.path, '/api/mobile/events/abc/setlist/generate');
      expect(req.method, 'POST');
      return _json(200, {
        'id': 9,
        'status': 'draft',
        'event_context': 'upbeat',
        'songs': [
          {'id': 1, 'type': 'song', 'position': 1, 'song_id': 10},
        ],
      });
    });

    final repo = SetlistEditorRepository(dio);
    final result = await repo.generate('abc', context: 'Keep it upbeat');

    expect(capturedBody!['context'], 'Keep it upbeat');
    expect(result.id, 9);
    expect(result.songs.length, 1);
  });

  test('generate omits empty context', () async {
    Map<String, dynamic>? capturedBody;

    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      return _json(200, {'id': 1, 'status': 'draft', 'songs': []});
    });

    final repo = SetlistEditorRepository(dio);
    await repo.generate('abc');

    expect(capturedBody!.containsKey('context'), isFalse);
  });

  test('refine parses wrapper response', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/events/abc/setlist/refine');
      expect(req.method, 'POST');
      final body = req.data as Map<String, dynamic>;
      expect(body['message'], 'shorter please');
      return _json(200, {
        'setlist': {'id': 1, 'status': 'draft', 'songs': []},
        'summary': 'Trimmed it.',
      });
    });

    final repo = SetlistEditorRepository(dio);
    final result = await repo.refine('abc', message: 'shorter please');

    expect(result.summary, 'Trimmed it.');
    expect(result.setlist.id, 1);
  });

  test('listPromptTemplates parses an array', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/3/setlist-prompt-templates');
      return _json(200, [
        {'id': 1, 'name': 'Wedding', 'prompt': 'High energy'},
        {'id': 2, 'name': 'Corporate', 'prompt': 'Tasteful'},
      ]);
    });

    final repo = SetlistEditorRepository(dio);
    final templates = await repo.listPromptTemplates(3);

    expect(templates.length, 2);
    expect(templates.first.name, 'Wedding');
  });

  // The shipped backend wraps prompt-template responses in a {data: ...}
  // envelope (matching attire-chips), while the setlist editor endpoints
  // return bare objects. These tests prove the wrapped path parses.

  test('listPromptTemplates parses a {data: [...]} envelope', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      return _json(200, {
        'data': [
          {'id': 1, 'name': 'Wedding', 'prompt': 'High energy'},
        ],
      });
    });

    final repo = SetlistEditorRepository(dio);
    final templates = await repo.listPromptTemplates(3);

    expect(templates.length, 1);
    expect(templates.first.name, 'Wedding');
  });

  test('createPromptTemplate parses a {data: {...}} envelope', () async {
    Map<String, dynamic>? capturedBody;

    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      expect(req.path, '/api/mobile/bands/3/setlist-prompt-templates');
      expect(req.method, 'POST');
      return _json(201, {
        'data': {'id': 7, 'name': 'Corporate', 'prompt': 'Tasteful'},
      });
    });

    final repo = SetlistEditorRepository(dio);
    final tpl = await repo.createPromptTemplate(3, name: 'Corporate', prompt: 'Tasteful');

    expect(capturedBody!['name'], 'Corporate');
    expect(tpl.id, 7);
    expect(tpl.name, 'Corporate');
  });

  test('updatePromptTemplate parses a {data: {...}} envelope', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/3/setlist-prompt-templates/7');
      expect(req.method, 'PATCH');
      return _json(200, {
        'data': {'id': 7, 'name': 'Renamed', 'prompt': 'Tasteful'},
      });
    });

    final repo = SetlistEditorRepository(dio);
    final tpl = await repo.updatePromptTemplate(3, 7, name: 'Renamed');

    expect(tpl.name, 'Renamed');
  });

  test('deletePromptTemplate sends DELETE to the scoped path', () async {
    var hit = false;

    dio.httpClientAdapter = _FakeAdapter((req) async {
      hit = true;
      expect(req.path, '/api/mobile/bands/3/setlist-prompt-templates/7');
      expect(req.method, 'DELETE');
      return _json(204, '');
    });

    final repo = SetlistEditorRepository(dio);
    await repo.deletePromptTemplate(3, 7);

    expect(hit, true);
  });
}
