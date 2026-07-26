import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/dashboard/data/dashboard_repository.dart';

/// Adapter that records the request and returns a canned JSON response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responseBody);

  final Map<String, dynamic> responseBody;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(responseBody),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DashboardRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
  return DashboardRepository(dio);
}

void main() {
  test('getDashboard sends to= when provided', () async {
    final adapter = _FakeAdapter({'events': [], 'upcoming_charts': []});
    await _repo(adapter).getDashboard(to: '2026-10-23');

    expect(adapter.lastRequest!.path, '/api/mobile/dashboard');
    expect(adapter.lastRequest!.queryParameters, {'to': '2026-10-23'});
  });

  test('getDashboard omits to= when null', () async {
    final adapter = _FakeAdapter({'events': [], 'upcoming_charts': []});
    await _repo(adapter).getDashboard();

    expect(adapter.lastRequest!.queryParameters, isEmpty);
  });

  test('loadNewerEvents hits load-newer with both bounds and parses events',
      () async {
    final adapter = _FakeAdapter({
      'events': [
        {
          'id': null,
          'key': 'virtual-rehearsal-3-2026-11-04',
          'title': 'Weekly Rehearsal',
          'date': '2026-11-04',
          'event_source': 'rehearsal_schedule',
        },
      ],
    });

    final events =
        await _repo(adapter).loadNewerEvents('2026-10-23', '2026-12-01');

    expect(adapter.lastRequest!.path, '/api/mobile/dashboard/load-newer');
    expect(adapter.lastRequest!.queryParameters,
        {'after_date': '2026-10-23', 'before_date': '2026-12-01'});
    expect(events, hasLength(1));
    expect(events.first.id, isNull);
    expect(events.first.key, 'virtual-rehearsal-3-2026-11-04');
    expect(events.first.isRehearsal, isTrue);
  });
}
