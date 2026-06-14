import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../storage/secure_storage.dart';
import 'api_endpoints.dart';
import '../../shared/providers/selected_band_provider.dart';

/// A callback invoked when the server returns 401. Typically used to navigate
/// to the login screen without requiring a BuildContext here.
typedef OnUnauthorized = void Function();

/// Key used in [RequestOptions.extra] to mark a request that has already been
/// retried after a token refresh, preventing infinite retry loops.
const _retriedAfterRefreshKey = '__retried_after_refresh';

class ApiClient {
  ApiClient({
    required SecureStorage storage,
    String? bandId,
    OnUnauthorized? onUnauthorized,
  })  : _storage = storage,
        _bandId = bandId,
        _onUnauthorized = onUnauthorized {
    _dio = _buildDio();
  }

  final SecureStorage _storage;
  final String? _bandId;
  final OnUnauthorized? _onUnauthorized;
  late final Dio _dio;

  Dio get dio => _dio;

  Dio _buildDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          if (_bandId != null) {
            options.headers['X-Band-ID'] = _bandId;
          }

          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;

          if (status == 401) {
            await _storage.deleteToken();
            await _storage.deleteBandId();
            _onUnauthorized?.call();
            handler.next(error);
            return;
          }

          // Reactively refresh a stale token: EnsureUserInBand returns this
          // exact message when the token lacks an ability the user actually has
          // (e.g. right after going solo). Refresh once, retry once.
          final data = error.response?.data;
          final isStaleTokenError = status == 403 &&
              data is Map &&
              data['message'] == 'Insufficient token permissions.';

          final req = error.requestOptions;
          final alreadyRetried = req.extra[_retriedAfterRefreshKey] == true;
          final isRefreshCall = req.path == ApiEndpoints.mobileTokenRefresh;

          // Single-flight is intentionally NOT enforced: if several requests
          // hit this 403 at once they each refresh. That's safe for this app's
          // low-concurrency mobile usage (the trigger is the brief post-goSolo
          // window). Revisit with a refresh lock only if 401-after-refresh
          // reports appear.
          if (isStaleTokenError && !alreadyRetried && !isRefreshCall) {
            try {
              final refreshed = await _dio.post<Map<String, dynamic>>(
                ApiEndpoints.mobileTokenRefresh,
              );
              final newToken = refreshed.data?['token'] as String?;
              if (newToken != null) {
                await _storage.writeToken(newToken);

                // Re-fire the original request. onRequest attaches the new token
                // from storage. Mark it so a second 403 can't loop.
                final retryOptions = req.copyWith(
                  extra: {...req.extra, _retriedAfterRefreshKey: true},
                );
                final retryResponse = await _dio.fetch<dynamic>(retryOptions);
                handler.resolve(retryResponse);
                return;
              }
            } catch (_) {
              // Fall through to surfacing the original error.
            }
          }

          handler.next(error);
        },
      ),
    );

    return dio;
  }
}

/// Simple provider — the [OnUnauthorized] callback is wired up in [app.dart]
/// using a navigator key after the widget tree is ready.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final bandId = ref.watch(selectedBandProvider).asData?.value?.toString();
  return ApiClient(storage: storage, bandId: bandId);
});
