import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/network_failure.dart';

final _options = RequestOptions(path: '/api/mobile/dashboard');

void main() {
  test('transport failures count as network failures', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      expect(
        isNetworkFailure(
          DioException(requestOptions: _options, type: type),
        ),
        isTrue,
        reason: '$type',
      );
    }
  });

  test('a socket failure wrapped as unknown counts', () {
    expect(
      isNetworkFailure(DioException(
        requestOptions: _options,
        error: const SocketException('Failed host lookup'),
      )),
      isTrue,
    );
  });

  test('a decode failure does not count', () {
    expect(
      isNetworkFailure(DioException(
        requestOptions: _options,
        error: const FormatException('Unexpected character'),
      )),
      isFalse,
      reason: 'a malformed body says nothing about connectivity',
    );
  });

  test('a response-bearing error never counts', () {
    expect(
      isNetworkFailure(DioException(
        requestOptions: _options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: _options, statusCode: 500),
      )),
      isFalse,
      reason: 'the round trip completed — the network is demonstrably fine',
    );
  });

  test('a cancellation never counts', () {
    expect(
      isNetworkFailure(DioException.requestCancelled(
        requestOptions: _options,
        reason: 'user left the screen',
      )),
      isFalse,
    );
  });

  test('non-Dio errors never count', () {
    expect(isNetworkFailure(StateError('nope')), isFalse);
    expect(isNetworkFailure(null), isFalse);
  });

  test('only the short-circuit carries OfflineException', () {
    final shortCircuited = DioException.connectionError(
      requestOptions: _options,
      reason: 'No connection to the server',
      error: const OfflineException(),
    );
    final realFailure = DioException.connectionError(
      requestOptions: _options,
      reason: 'Failed host lookup',
    );

    expect(isOfflineShortCircuit(shortCircuited), isTrue);
    expect(isOfflineShortCircuit(realFailure), isFalse);
    expect(isNetworkFailure(shortCircuited), isTrue);
  });
}
