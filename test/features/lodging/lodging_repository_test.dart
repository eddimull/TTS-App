import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/lodging_repository.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responseBody, {this.statusCode = 200});

  final Map<String, dynamic> responseBody;
  final int statusCode;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

LodgingRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
  return LodgingRepository(dio);
}

void main() {
  test('getLodgings hits band-scoped endpoint and parses envelope', () async {
    final adapter = _FakeAdapter({
      'lodgings': [
        {
          'id': 1,
          'name': 'Hampton Inn',
          'check_in_at': '2030-08-14 15:00:00',
          'check_out_at': '2030-08-16 11:00:00',
          'room_count': 2,
          'attachment_count': 0,
        },
      ],
      'can_write': true,
    });

    final result = await _repo(adapter).getLodgings(7);

    expect(adapter.lastRequest!.path, '/api/mobile/bands/7/lodgings');
    expect(result.lodgings.single.name, 'Hampton Inn');
    expect(result.canWrite, isTrue);
  });

  test('createLodging posts payload with rooms', () async {
    final adapter = _FakeAdapter({
      'lodging': {
        'id': 9,
        'name': 'New Hotel',
        'check_in_at': '2030-08-14 15:00:00',
        'check_out_at': '2030-08-16 11:00:00',
        'rooms': [],
        'attachments': [],
      },
    });

    final lodging = await _repo(adapter).createLodging(
      7,
      name: 'New Hotel',
      checkInAt: '2030-08-14 15:00:00',
      checkOutAt: '2030-08-16 11:00:00',
      rooms: const [LodgingRoom(label: 'King')],
    );

    expect(adapter.lastRequest!.method, 'POST');
    final sent = adapter.lastRequest!.data as Map<String, dynamic>;
    expect(sent['name'], 'New Hotel');
    expect(sent['rooms'], [
      {'label': 'King'}
    ]);
    expect(lodging.id, 9);
  });

  test('updateLodging patches only the given fields', () async {
    final adapter = _FakeAdapter({
      'lodging': {
        'id': 9,
        'name': 'Renamed',
        'check_in_at': '2030-08-14 15:00:00',
        'check_out_at': '2030-08-16 11:00:00',
        'rooms': [],
        'attachments': [],
      },
    });

    await _repo(adapter).updateLodging(7, 9, {'name': 'Renamed'});

    expect(adapter.lastRequest!.method, 'PATCH');
    expect(adapter.lastRequest!.path, '/api/mobile/bands/7/lodgings/9');
    expect(adapter.lastRequest!.data, {'name': 'Renamed'});
  });

  test('uploadAttachment posts multipart file', () async {
    final adapter = _FakeAdapter({
      'attachment': {
        'id': 3,
        'filename': 'map.jpg',
        'mime_type': 'image/jpeg',
        'file_size': 5,
        'url': 'http://x/api/mobile/lodging-attachments/3',
      },
    }, statusCode: 201);

    final attachment = await _repo(adapter).uploadAttachment(
      7,
      9,
      bytes: [1, 2, 3, 4, 5],
      filename: 'map.jpg',
    );

    expect(adapter.lastRequest!.data, isA<FormData>());
    expect(attachment.id, 3);
  });
}
