import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/media/data/media_repository.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions o) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<List<int>>? requestStream, Future<void>? cancelFuture) =>
      handler(options);
}

ResponseBody _json(Map<String, dynamic> body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );

void main() {
  test('resume skips already-uploaded chunks', () async {
    final tmp = await Directory.systemTemp.createTemp();
    // 5 MB file => 3 chunks at 2MB
    final file = File('${tmp.path}/big.bin')
      ..writeAsBytesSync(List.filled(5 * 1024 * 1024, 1));
    final chunkPosts = <int>[];

    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    dio.httpClientAdapter = _FakeAdapter((o) async {
      if (o.path.endsWith('/initiate')) return _json({'upload_id': 'u1'});
      if (o.method == 'GET' && o.path.endsWith('/u1')) {
        return _json(
            {'total_chunks': 3, 'chunks_uploaded': 1, 'status': 'uploading'});
      }
      if (o.path.contains('/chunk')) {
        chunkPosts.add(1);
        return _json({'success': true});
      }
      // complete
      return _json({
        'media': {
          'id': 1,
          'filename': 'big.bin',
          'media_type': 'other',
          'mime_type': 'application/octet-stream',
          'file_size': 5,
        }
      });
    });

    final repo = MediaRepository(dio);
    await repo.uploadFile(7, file, eventId: 3, existingUploadId: 'u1');

    // chunk 0 already uploaded server-side; only chunks 1 and 2 should be POSTed
    expect(chunkPosts.length, 2);
  });

  test('resume forwards the cancelToken to the status GET', () async {
    final tmp = await Directory.systemTemp.createTemp();
    final file = File('${tmp.path}/big.bin')
      ..writeAsBytesSync(List.filled(5 * 1024 * 1024, 1));
    CancelToken? statusGetToken;
    final token = CancelToken();

    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    dio.httpClientAdapter = _FakeAdapter((o) async {
      if (o.method == 'GET' && o.path.endsWith('/u1')) {
        statusGetToken = o.cancelToken;
        return _json(
            {'total_chunks': 3, 'chunks_uploaded': 1, 'status': 'uploading'});
      }
      if (o.path.contains('/chunk')) return _json({'success': true});
      return _json({
        'media': {
          'id': 1,
          'filename': 'big.bin',
          'media_type': 'other',
          'mime_type': 'application/octet-stream',
          'file_size': 5,
        }
      });
    });

    final repo = MediaRepository(dio);
    await repo.uploadFile(7, file,
        eventId: 3, existingUploadId: 'u1', cancelToken: token);

    expect(statusGetToken, same(token));
  });

  test('fresh upload posts all chunks and returns media', () async {
    final tmp = await Directory.systemTemp.createTemp();
    final file = File('${tmp.path}/small.bin')
      ..writeAsBytesSync(List.filled(3 * 1024 * 1024, 1)); // 2 chunks
    var initiated = false;
    String? capturedUploadId;

    final dio = Dio(BaseOptions(baseUrl: 'http://x'));
    dio.httpClientAdapter = _FakeAdapter((o) async {
      if (o.path.endsWith('/initiate')) {
        initiated = true;
        return _json({'upload_id': 'fresh1'});
      }
      if (o.path.contains('/chunk')) return _json({'success': true});
      return _json({
        'media': {
          'id': 2,
          'filename': 'small.bin',
          'media_type': 'other',
          'mime_type': 'application/octet-stream',
          'file_size': 3,
        }
      });
    });

    final repo = MediaRepository(dio);
    final media =
        repo.uploadFile(7, file, onInitiated: (id) => capturedUploadId = id);

    final result = await media;
    expect(initiated, isTrue);
    expect(capturedUploadId, 'fresh1');
    expect(result.id, 2);
  });
}
