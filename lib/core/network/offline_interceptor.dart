import 'package:dio/dio.dart';

import 'api_response_cache.dart';
import 'network_failure.dart';
import 'reachability.dart';

/// `extra` flag marking a request as the reachability probe. Probes bypass the
/// circuit breaker (testing the water is their whole job) and the cache.
const String kProbeRequestKey = '__reachability_probe';

/// `extra` flag set on a response that was replayed from disk rather than
/// fetched. Screens can use it to caveat what they're showing.
const String kFromCacheKey = '__from_cache';

/// `extra` value (milliseconds since epoch) recording when a replayed response
/// was originally fetched.
const String kCachedAtKey = '__cached_at';

/// Keeps the app usable when the server can't be reached.
///
/// Three jobs, in the order they matter to someone standing on dead Wi-Fi:
///
/// 1. **Fail fast.** Once a request has failed at the transport level, later
///    requests are rejected immediately instead of each waiting out its own
///    timeout. A tap gets an answer at once rather than a spinner.
/// 2. **Fall back to disk.** A GET that can't reach the server is answered
///    from the last successful response for that endpoint, so lists and detail
///    screens still render.
/// 3. **Notice recovery.** Any completed round trip closes the circuit, which
///    is what clears the offline banner and lets the shell refetch.
///
/// Writes are deliberately *not* replayed or queued — a booking edit that
/// never reached the server must surface as a failure, not silently appear to
/// have worked.
class OfflineInterceptor extends Interceptor {
  OfflineInterceptor({
    required Reachability reachability,
    ApiResponseCache? cache,
    String? bandId,
  })  : _reachability = reachability,
        _cache = cache,
        _bandId = bandId;

  final Reachability _reachability;
  final ApiResponseCache? _cache;

  /// The band this client is scoped to — part of every cache key.
  final String? _bandId;

  /// Paths never written to the response cache. `SharedPreferences` is not
  /// encrypted, and the session (user, bands, account profile) already has an
  /// offline home in `SecureStorage` — see
  /// `AuthNotifier._restoreCachedSession`.
  static const _uncacheablePathPrefixes = [
    '/api/mobile/auth/',
    '/api/mobile/token/',
    '/api/mobile/account',
  ];

  bool _isProbe(RequestOptions options) =>
      options.extra[kProbeRequestKey] == true;

  bool _isCacheable(RequestOptions options) {
    if (_cache == null) return false;
    if (options.method.toUpperCase() != 'GET') return false;
    if (_isProbe(options)) return false;
    final path = options.uri.path;
    return !_uncacheablePathPrefixes.any(path.startsWith);
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (_isProbe(options)) {
      handler.next(options);
      return;
    }

    if (_reachability.shouldShortCircuit()) {
      handler.reject(
        DioException.connectionError(
          requestOptions: options,
          reason: 'No connection to the server',
          error: const OfflineException(),
        ),
        // Send it down the error chain rather than straight back to the
        // caller, so [onError] below still gets to answer it from the cache.
        true,
      );
      return;
    }

    _reachability.recordAttempt();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _reachability.recordSuccess();

    final options = response.requestOptions;
    final status = response.statusCode ?? 0;
    if (_isCacheable(options) && status >= 200 && status < 300) {
      final body = response.data;
      if (body is Map || body is List) {
        _cache!.write(
          ApiResponseCache.keyFor(options, bandId: _bandId),
          statusCode: status,
          body: body,
        );
      }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (isNetworkFailure(err)) {
      // A short-circuited request never touched the network, so it can't be
      // evidence about it — recording it would keep pushing the retry window
      // out for as long as the UI keeps asking.
      if (!isOfflineShortCircuit(err)) {
        _reachability.recordFailure();
      }

      final cached = _cachedResponseFor(err.requestOptions);
      if (cached != null) {
        handler.resolve(cached);
        return;
      }
    } else if (err.response != null) {
      // The server answered — badly, but it answered. The network is fine.
      _reachability.recordSuccess();
    }

    handler.next(err);
  }

  Response<dynamic>? _cachedResponseFor(RequestOptions options) {
    if (!_isCacheable(options)) return null;

    final cached = _cache!.read(
      ApiResponseCache.keyFor(options, bandId: _bandId),
    );
    if (cached == null) return null;

    // Stamped on the *request* options as well as the response: Dio rebuilds
    // the response object when it casts `Response<dynamic>` to the caller's
    // `Response<T>`, and `requestOptions` is what survives that intact.
    options.extra[kFromCacheKey] = true;
    options.extra[kCachedAtKey] = cached.cachedAt.millisecondsSinceEpoch;

    return Response<dynamic>(
      requestOptions: options,
      data: cached.body,
      statusCode: cached.statusCode,
      statusMessage: 'OK (cached)',
      extra: Map<String, dynamic>.from(options.extra),
    );
  }
}
