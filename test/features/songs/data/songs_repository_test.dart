import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/songs/data/models/song.dart';
import 'package:tts_bandmate/features/songs/data/songs_repository.dart';

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

Map<String, dynamic> _songJson(int id, String title, {bool active = true}) => {
      'id': id,
      'band_id': 1,
      'title': title,
      'artist': '',
      'song_key': '',
      'genre': '',
      'bpm': 0,
      'notes': '',
      'rating': null,
      'energy': null,
      'active': active,
      'lead_singer': null,
      'transition_song': null,
      'charts': <Map<String, dynamic>>[],
    };

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio();
  });

  test('getSongs hits the band songs path and parses songs + genres', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/songs');
      expect(req.method, 'GET');
      expect(req.queryParameters, isEmpty);
      return _json(200, {
        'songs': [_songJson(10, 'September')],
        'genres': ['Funk', 'Soul'],
      });
    });

    final repo = SongsRepository(dio);
    final result = await repo.getSongs(1);

    expect(result.songs, hasLength(1));
    expect(result.songs.first.title, 'September');
    expect(result.genres, ['Funk', 'Soul']);
  });

  test('getSongs passes include_inactive=1 when requested', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.queryParameters, {'include_inactive': 1});
      return _json(200, {'songs': <Map<String, dynamic>>[], 'genres': <String>[]});
    });

    final repo = SongsRepository(dio);
    await repo.getSongs(1, includeInactive: true);
  });

  test('createSong POSTs toUpdateJson and parses the song envelope', () async {
    Map<String, dynamic>? capturedBody;
    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      expect(req.path, '/api/mobile/bands/1/songs');
      expect(req.method, 'POST');
      return _json(201, {'song': _songJson(99, 'New Song')});
    });

    final repo = SongsRepository(dio);
    final created = await repo.createSong(
      1,
      const Song(id: 0, bandId: 1, title: 'New Song', bpm: 120),
    );

    expect(capturedBody!['title'], 'New Song');
    expect(capturedBody!['bpm'], 120);
    expect(capturedBody!['artist'], isNull);
    expect(created.id, 99);
  });

  test('updateSong PATCHes the song path', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/songs/7');
      expect(req.method, 'PATCH');
      expect((req.data as Map<String, dynamic>)['title'], 'Renamed');
      return _json(200, {'song': _songJson(7, 'Renamed')});
    });

    final repo = SongsRepository(dio);
    final updated =
        await repo.updateSong(1, const Song(id: 7, bandId: 1, title: 'Renamed'));

    expect(updated.title, 'Renamed');
  });

  test('deleteSong DELETEs the song path', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/songs/7');
      expect(req.method, 'DELETE');
      return _json(200, {'message': 'Song deleted.'});
    });

    final repo = SongsRepository(dio);
    await repo.deleteSong(1, 7);
  });

  test('lookupBpm GETs /api/mobile/songs/lookup with title and artist', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/songs/lookup');
      expect(req.method, 'GET');
      expect(req.queryParameters,
          {'title': 'Superstition', 'artist': 'Stevie Wonder'});
      return _json(200, {'bpm': 100, 'song_key': 'E♭m'});
    });

    final repo = SongsRepository(dio);
    final result =
        await repo.lookupBpm(title: 'Superstition', artist: 'Stevie Wonder');

    expect(result['bpm'], 100);
    expect(result['song_key'], 'E♭m');
  });

  test('lookupBpm omits an empty artist', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.queryParameters, {'title': 'Superstition'});
      return _json(200, {'bpm': 100});
    });

    final repo = SongsRepository(dio);
    await repo.lookupBpm(title: 'Superstition', artist: '');
  });
}
