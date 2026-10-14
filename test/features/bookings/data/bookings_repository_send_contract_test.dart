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
  Future<RequestOptions> send({
    required List<int> signerIds,
    List<int>? ccIds,
  }) async {
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
            'status': 'pending',
            'contract_option': 'default',
            'contacts': [],
            'events': [],
          }
        });
      });
    final repo = BookingsRepository(dio);
    final detail = ccIds == null
        ? await repo.sendContract(1, 42, signerIds: signerIds)
        : await repo.sendContract(1, 42, signerIds: signerIds, ccIds: ccIds);
    expect(detail.id, 42);
    return captured;
  }

  test('sendContract posts signer_ids and cc_ids arrays only', () async {
    final req = await send(signerIds: [3, 5], ccIds: [8]);
    expect(req.method, 'POST');
    expect(req.path, '/api/mobile/bands/1/bookings/42/contract/send');
    expect(req.data, {
      'signer_ids': [3, 5],
      'cc_ids': [8],
    });
  });

  test('sendContract defaults cc_ids to empty and omits legacy keys',
      () async {
    final req = await send(signerIds: [3]);
    final body = req.data as Map;
    expect(body['signer_ids'], [3]);
    expect(body['cc_ids'], isEmpty);
    expect(body.containsKey('signer_id'), isFalse);
    expect(body.containsKey('cc_id'), isFalse);
  });
}
