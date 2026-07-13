import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/data/library_repository.dart';

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

Map<String, dynamic> _chartJson({Map<String, dynamic>? song}) => {
      'id': 3,
      'band_id': 1,
      'title': 'Horn Chart',
      'composer': '',
      'description': '',
      'price': 0,
      'public': false,
      'uploads_count': 0,
      'song': song,
    };

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio();
  });

  test('createChart includes song_id when provided', () async {
    Map<String, dynamic>? capturedBody;
    dio.httpClientAdapter = _FakeAdapter((req) async {
      capturedBody = req.data as Map<String, dynamic>;
      expect(req.path, '/api/mobile/bands/1/charts');
      expect(req.method, 'POST');
      return _json(201, {
        'chart': _chartJson(song: {'id': 5, 'title': 'September', 'artist': ''}),
      });
    });

    final repo = LibraryRepository(dio);
    final chart = await repo.createChart(1, title: 'Horn Chart', songId: 5);

    expect(capturedBody!['song_id'], 5);
    expect(chart.song!.id, 5);
  });

  test('createChart omits song_id when null', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect((req.data as Map<String, dynamic>).containsKey('song_id'), false);
      return _json(201, {'chart': _chartJson()});
    });

    final repo = LibraryRepository(dio);
    await repo.createChart(1, title: 'Horn Chart');
  });

  test('updateChartSong PATCHes the chart with song_id', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.path, '/api/mobile/bands/1/charts/3');
      expect(req.method, 'PATCH');
      expect(req.data, {'song_id': 5});
      return _json(200, {
        'chart': _chartJson(song: {'id': 5, 'title': 'September', 'artist': ''}),
      });
    });

    final repo = LibraryRepository(dio);
    final chart = await repo.updateChartSong(1, 3, songId: 5);

    expect(chart.song!.title, 'September');
  });

  test('updateChartSong with null unlinks', () async {
    dio.httpClientAdapter = _FakeAdapter((req) async {
      expect(req.data, {'song_id': null});
      return _json(200, {'chart': _chartJson()});
    });

    final repo = LibraryRepository(dio);
    final chart = await repo.updateChartSong(1, 3, songId: null);

    expect(chart.song, isNull);
  });
}
