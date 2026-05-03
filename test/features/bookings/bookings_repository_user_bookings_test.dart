import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    lastRequest = options;
    return handler(options);
  }
}

ResponseBody _json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(encoded, status, headers: {
    'content-type': ['application/json'],
  });
}

void main() {
  group('BookingsRepository.getAllUserBookings', () {
    test('hits /api/mobile/me/bookings and parses bookings with band', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {
          'bookings': [
            {
              'id': 1,
              'name': 'Wedding',
              'date': '2026-06-01',
              'is_paid': false,
              'contacts': [],
              'band': {
                'id': 10,
                'name': 'Test Band',
                'is_owner': true,
                'is_personal': false,
                'logo_url': null,
              },
            },
            {
              'id': 2,
              'name': 'Church',
              'date': '2026-06-02',
              'is_paid': false,
              'contacts': [],
              'band': {
                'id': 99,
                'name': "Eddie's Band",
                'is_owner': true,
                'is_personal': true,
                'logo_url': null,
              },
            },
          ],
        });
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      final results = await repo.getAllUserBookings();

      expect(adapter.lastRequest!.method, equals('GET'));
      expect(adapter.lastRequest!.path, equals('/api/mobile/me/bookings'));
      expect(adapter.lastRequest!.queryParameters, isEmpty);

      expect(results, hasLength(2));
      expect(results[0].band!.id, equals(10));
      expect(results[0].band!.isPersonal, isFalse);
      expect(results[1].band!.isPersonal, isTrue);
    });

    test('passes status, upcomingOnly, year as query params', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(
        status: 'confirmed',
        upcomingOnly: true,
        year: 2026,
      );

      expect(adapter.lastRequest!.queryParameters, equals({
        'status': 'confirmed',
        'upcoming': '1',
        'year': '2026',
      }));
    });

    test('omits unset filter params', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(year: 2026);

      expect(adapter.lastRequest!.queryParameters, equals({'year': '2026'}));
    });

    test('passes from + to as YYYY-MM-DD query params', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 6, 30),
      );

      expect(adapter.lastRequest!.queryParameters, equals({
        'from': '2026-01-01',
        'to': '2026-06-30',
      }));
    });

    test('passes only from when to is null', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(from: DateTime(2026, 3, 15));

      expect(adapter.lastRequest!.queryParameters, equals({'from': '2026-03-15'}));
    });

    test('passes only to when from is null', () async {
      final adapter = _StubAdapter((req) async {
        return _json(200, {'bookings': []});
      });
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = adapter;

      final repo = BookingsRepository(dio);
      await repo.getAllUserBookings(to: DateTime(2026, 12, 31));

      expect(adapter.lastRequest!.queryParameters, equals({'to': '2026-12-31'}));
    });
  });
}
