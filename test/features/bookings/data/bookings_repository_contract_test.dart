import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_repository.dart';
import 'package:tts_bandmate/features/bookings/data/models/contract_term.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final ResponseBody Function(RequestOptions opts) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return handler(options);
  }
}

void main() {
  group('BookingsRepository contract methods', () {
    test('saveContractTerms POSTs terms and parses booking', () async {
      late RequestOptions captured;
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _StubAdapter((opts) {
        captured = opts;
        return ResponseBody.fromString(
          '{"booking":{"id":7,"name":"X","start_date":"2026-05-11","end_date":"2026-05-11","event_count":1,"is_multi_event":false,"is_paid":false,"contacts":[],"events":[]}}',
          200,
          headers: {
            'content-type': ['application/json']
          },
        );
      });

      final repo = BookingsRepository(dio);
      final result = await repo.saveContractTerms(1, 7, [
        const ContractTerm(id: 0, title: 'T', content: 'C'),
      ]);

      expect(captured.method, 'POST');
      expect(captured.uri.path, '/api/mobile/bands/1/bookings/7/contract/terms');
      expect((captured.data as Map)['custom_terms'], [
        {'title': 'T', 'content': 'C'}
      ]);
      expect(result.id, 7);
    });

    test('fetchContractHistory parses results array', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _StubAdapter((opts) {
        return ResponseBody.fromString(
          '{"history":{"results":[{"id":"e1","action":"Document Sent","action_code":6,"user_email":"a@b.com","description":"d","status":"completed"}]}}',
          200,
          headers: {
            'content-type': ['application/json']
          },
        );
      });

      final repo = BookingsRepository(dio);
      final history = await repo.fetchContractHistory('env-1');
      expect(history.length, 1);
      expect(history.first.action, 'Document Sent');
    });

    test('fetchContractHistory falls back to flat history array', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _StubAdapter((opts) {
        return ResponseBody.fromString(
          '{"history":[{"id":"e1","action":"X","action_code":1,"user_email":"","description":"","status":"info"}]}',
          200,
          headers: {
            'content-type': ['application/json']
          },
        );
      });

      final repo = BookingsRepository(dio);
      final history = await repo.fetchContractHistory('env-1');
      expect(history.length, 1);
    });

    test('downloadContractPdf returns bytes', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _StubAdapter((opts) {
        return ResponseBody.fromBytes(
          [0x25, 0x50, 0x44, 0x46],
          200,
          headers: {
            'content-type': ['application/pdf']
          },
        );
      });

      final repo = BookingsRepository(dio);
      final bytes = await repo.downloadContractPdf(1, 7);
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, 4);
      expect(bytes[0], 0x25);
    });

    test('fetchContractViewUrl returns url string', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _StubAdapter((opts) {
        return ResponseBody.fromString(
          '{"url":"https://example.com/view?signature=xyz","expires_at":"2026-05-11T13:00:00Z"}',
          200,
          headers: {
            'content-type': ['application/json']
          },
        );
      });

      final repo = BookingsRepository(dio);
      final url = await repo.fetchContractViewUrl(1, 7);
      expect(url, 'https://example.com/view?signature=xyz');
    });
  });
}
