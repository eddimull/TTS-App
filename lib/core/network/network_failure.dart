import 'package:dio/dio.dart';

/// Marker error attached to a [DioException] that the client rejected without
/// ever putting it on the wire, because the API is known to be unreachable.
///
/// Distinguishing this from a real transport failure matters for retries: a
/// short-circuited request proves nothing new about the network, so retrying
/// it on a backoff schedule just burns cycles (see `_retryPolicy` in
/// main.dart).
class OfflineException implements Exception {
  const OfflineException();

  @override
  String toString() => 'OfflineException: the server is unreachable';
}

/// Runtime type names of the platform exceptions Dio wraps in
/// [DioExceptionType.unknown] when the transport — not the server — failed.
///
/// Matched by name rather than by type so this file stays importable on web
/// (SocketException and friends live in `dart:io`).
const _transportErrorTypeNames = {
  'SocketException',
  'HandshakeException',
  'TlsException',
  'HttpException',
  'ClientException', // package:http, used by the web adapter
  'TimeoutException',
  'OfflineException',
  'WebSocketException',
};

/// True when [error] means "the app could not reach its server" — as opposed
/// to "the server answered, and the answer was an error".
///
/// A [DioException] carrying a [DioException.response] is always the latter:
/// the round trip completed, so the network is demonstrably fine. Only the
/// no-response failures below say anything about connectivity.
bool isNetworkFailure(Object? error) {
  if (error is! DioException) return false;

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return true;
    case DioExceptionType.unknown:
      // `unknown` is Dio's catch-all: it covers transport failures, but also
      // response-decoding failures, which say nothing about the network. Only
      // treat it as a network failure when the wrapped error is a transport
      // exception AND no response ever arrived.
      if (error.response != null) return false;
      final inner = error.error;
      if (inner == null) return false;
      return _transportErrorTypeNames.contains(inner.runtimeType.toString());
    case DioExceptionType.badResponse:
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
      return false;
  }
}

/// True when [error] is a request this client refused to send because it
/// already knew the server was unreachable.
bool isOfflineShortCircuit(Object? error) =>
    error is DioException && error.error is OfflineException;
