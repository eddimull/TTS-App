import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/rehearsals/data/rehearsals_repository.dart';

/// Adapter that records the request and returns a canned JSON response.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responseBody);

  final Map<String, dynamic> responseBody;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
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

void main() {
  test('setCancelled PATCHes the cancelled endpoint and parses the detail', () async {
    final adapter = _FakeAdapter({
      'rehearsal': {
        'id': 42,
        'date': '2099-01-05',
        'time': '19:00',
        'venue_name': 'The Shed',
        'is_cancelled': true,
        'notes': null,
        'event_key': 'k-1',
        'schedule': {'id': 7, 'name': 'Tuesday Practice', 'location_name': 'The Shed'},
        'associated_bookings': [],
      },
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;
    final repo = RehearsalsRepository(dio);

    final detail = await repo.setCancelled(42, true);

    expect(adapter.lastRequest!.method, 'PATCH');
    expect(adapter.lastRequest!.path, '/api/mobile/rehearsals/42/cancelled');
    expect(adapter.lastRequest!.data, {'is_cancelled': true});
    expect(detail.id, 42);
    expect(detail.isCancelled, isTrue);
  });

  test('getSchedules passes until and include_virtual and parses new fields',
      () async {
    final adapter = _FakeAdapter({
      'schedules': [
        {
          'id': 7,
          'name': 'Weekly Rehearsal',
          'frequency': 'weekly',
          'recurrence_label': 'Every Wednesday at 7:00 PM',
          'active': true,
          'upcoming_rehearsals': [
            {
              'id': 42,
              'date': '2026-07-29',
              'is_cancelled': false,
              'is_virtual': false,
            },
            {
              'id': null,
              'date': '2026-08-05',
              'event_key': 'virtual-rehearsal-7-2026-08-05',
              'is_cancelled': false,
              'is_virtual': true,
            },
          ],
        },
      ],
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    final repo = RehearsalsRepository(dio);

    final schedules = await repo.getSchedules(1,
        until: '2026-10-23', includeVirtual: true);

    expect(adapter.lastRequest!.path, '/api/mobile/bands/1/rehearsal-schedules');
    expect(adapter.lastRequest!.queryParameters,
        {'until': '2026-10-23', 'include_virtual': 1});

    final schedule = schedules.single;
    expect(schedule.recurrenceLabel, 'Every Wednesday at 7:00 PM');
    expect(schedule.upcomingRehearsals, hasLength(2));
    expect(schedule.upcomingRehearsals[0].id, 42);
    expect(schedule.upcomingRehearsals[0].isVirtual, isFalse);
    expect(schedule.upcomingRehearsals[1].id, isNull);
    expect(schedule.upcomingRehearsals[1].isVirtual, isTrue);
    expect(schedule.upcomingRehearsals[1].eventKey,
        'virtual-rehearsal-7-2026-08-05');
  }, skip: 'enabled in Task 9');
}
