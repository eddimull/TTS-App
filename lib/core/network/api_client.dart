import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../storage/secure_storage.dart';
import '../../shared/providers/selected_band_provider.dart';

/// A callback invoked when the server returns 401. Typically used to navigate
/// to the login screen without requiring a BuildContext here.
typedef OnUnauthorized = void Function();

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
            options.headers['X-Band-ID'] = _bandId!;
          }

          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _storage.deleteToken();
            await _storage.deleteBandId();
            _onUnauthorized?.call();
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
