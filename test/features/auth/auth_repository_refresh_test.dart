import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/auth_repository.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';

// Hand-rolled Dio fake — mirrors the pattern used throughout this test suite
// (see test/features/band_settings/band_settings_repository_test.dart).
class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final body = _responses[path];
    if (body == null) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  test('refreshToken posts to refresh endpoint and returns new token', () async {
    final dio = _FakeDio({
      ApiEndpoints.mobileTokenRefresh: {
        'token': 'new-token-123',
        'user': {'id': 1, 'name': 'Wes', 'email': 'w@example.com', 'avatar_url': null},
        'bands': <dynamic>[],
      },
    });

    final repo = AuthRepository(dio);
    final result = await repo.refreshToken();

    expect(result.token, 'new-token-123');
  });
}
