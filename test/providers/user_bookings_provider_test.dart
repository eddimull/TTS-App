import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/providers/bookings_provider.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) async {
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
  test('userBookingsProvider fetches via /api/mobile/me/bookings', () async {
    final adapter = _StubAdapter((req) async {
      return _json(200, {
        'bookings': [
          {
            'id': 1,
            'name': 'Gig',
            'date': '2026-06-01',
            'is_paid': false,
            'contacts': [],
            'band': {
              'id': 10,
              'name': 'A',
              'is_owner': true,
              'is_personal': false,
              'logo_url': null,
            },
          },
        ],
      });
    });
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;

    final container = ProviderContainer(overrides: [
      bookingsRepositoryProvider.overrideWithValue(BookingsRepository(dio)),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(userBookingsProvider.future);

    expect(adapter.lastRequest!.path, equals('/api/mobile/me/bookings'));
    expect(adapter.lastRequest!.queryParameters, isEmpty);
    expect(result, hasLength(1));
    expect(result.first.band!.id, equals(10));
  });
}
