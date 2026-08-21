import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// `extra` key for overriding [DeadlineHttpClientAdapter]'s deadline on a
/// single request. Value must be a [Duration].
const String kRequestDeadlineKey = '__request_deadline';

/// Wraps another [HttpClientAdapter] with a hard wall-clock deadline on
/// getting response headers back.
///
/// Dio's own `connectTimeout` is not a complete backstop. On `dart:io` it is
/// applied to `HttpClient.connectionTimeout`, whose timer only starts once the
/// host has been *resolved* — so a DNS lookup that never gets an answer (the
/// normal outcome on Wi-Fi with no working upstream) is outside its reach and
/// can hang for as long as the platform resolver keeps retrying. Wrapping
/// `fetch` covers the whole attempt: resolution, connection, TLS and
/// time-to-first-byte.
///
/// The response *body* is still governed by Dio's `receiveTimeout`, since
/// `fetch` completes as soon as the headers arrive.
class DeadlineHttpClientAdapter implements HttpClientAdapter {
  DeadlineHttpClientAdapter(
    this._inner, {
    required this.deadline,
    required this.uploadDeadline,
  });

  final HttpClientAdapter _inner;

  /// Applied to ordinary requests.
  final Duration deadline;

  /// Applied to multipart requests. `fetch` does not complete until the whole
  /// body has been sent, so an upload legitimately outlives [deadline].
  final Duration uploadDeadline;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final effective = _deadlineFor(options);
    return _inner.fetch(options, requestStream, cancelFuture).timeout(
          effective,
          onTimeout: () => throw DioException.connectionTimeout(
            timeout: effective,
            requestOptions: options,
          ),
        );
  }

  Duration _deadlineFor(RequestOptions options) {
    final override = options.extra[kRequestDeadlineKey];
    if (override is Duration) return override;
    if (options.data is FormData) return uploadDeadline;
    return deadline;
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
