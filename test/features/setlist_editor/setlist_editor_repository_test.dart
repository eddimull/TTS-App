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
    expect(result.status, 'ready');
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
}
