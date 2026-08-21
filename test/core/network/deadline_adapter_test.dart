import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/deadline_adapter.dart';

/// Stands in for a request that never gets an answer — the shape of a DNS
/// lookup on Wi-Fi with no working upstream, which `connectTimeout` alone
/// does not bound.
class _HangingAdapter implements HttpClientAdapter {
  final _never = Completer<ResponseBody>();
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) {
    calls++;
    return _never.future;
  }
}

RequestOptions _options({Object? data, Duration? deadline}) => RequestOptions(
      path: '/api/mobile/dashboard',
      baseUrl: 'https://example.test',
      data: data,
      extra: {if (deadline != null) kRequestDeadlineKey: deadline},
    );

void main() {
  test('a request that never answers fails at the deadline', () async {
    final adapter = DeadlineHttpClientAdapter(
      _HangingAdapter(),
      deadline: const Duration(milliseconds: 50),
      uploadDeadline: const Duration(seconds: 30),
    );

    await expectLater(
      adapter.fetch(_options(), null, null),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.connectionTimeout,
        ),
      ),
    );
  });

  test('multipart uploads get the longer deadline', () async {
    final adapter = DeadlineHttpClientAdapter(
      _HangingAdapter(),
      deadline: const Duration(milliseconds: 50),
      uploadDeadline: const Duration(seconds: 30),
    );

    final upload = adapter.fetch(
      _options(data: FormData.fromMap({'name': 'chart'})),
      null,
      null,
    );

    var settled = false;
    unawaited(upload.then<void>(
      (_) => settled = true,
      onError: (Object _) => settled = true,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(settled, isFalse,
        reason: 'an upload must not be cut off by the short deadline');
  });

  test('a per-request override wins', () async {
    final adapter = DeadlineHttpClientAdapter(
      _HangingAdapter(),
      deadline: const Duration(seconds: 30),
      uploadDeadline: const Duration(seconds: 30),
    );

    await expectLater(
      adapter.fetch(
        _options(deadline: const Duration(milliseconds: 50)),
        null,
        null,
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('a response that arrives in time passes straight through', () async {
    final body = ResponseBody.fromString('{}', 200);
    final adapter = DeadlineHttpClientAdapter(
      _ImmediateAdapter(body),
      deadline: const Duration(seconds: 5),
      uploadDeadline: const Duration(seconds: 30),
    );

    expect(await adapter.fetch(_options(), null, null), same(body));
  });
}

class _ImmediateAdapter implements HttpClientAdapter {
  _ImmediateAdapter(this.body);
  final ResponseBody body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async =>
      body;
}
