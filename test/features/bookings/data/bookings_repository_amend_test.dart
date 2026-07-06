import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
          RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      handler(o);
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );

void main() {
  test('amendContract POSTs to the amend endpoint and parses the booking',
      () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        captured = req;
        return _json(200, {
          'booking': {
            'id': 42,
            'name': 'Wedding',
            'start_date': '2026-08-01',
            'end_date': '2026-08-01',
            'event_count': 1,
            'is_multi_event': false,
            'is_paid': false,
            'status': 'draft',
            'contract_option': 'default',
            'contract': {'id': 9, 'status': 'pending', 'envelope_id': null},
            'contacts': [],
            'events': [],
          }
        });
      });

    final repo = BookingsRepository(dio);
    final detail = await repo.amendContract(1, 42);

    expect(captured.method, 'POST');
    expect(captured.path, '/api/mobile/bands/1/bookings/42/contract/amend');
    expect(detail.status, 'draft');
    expect(detail.contract?.status, 'pending');
    expect(detail.contract?.envelopeId, isNull);
  });
}
