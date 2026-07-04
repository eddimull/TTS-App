import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/auth_repository.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';

class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;
  Object? lastPostData;

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
    lastPostData = data;
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
  test('socialLogin posts provider payload and parses the standard envelope',
      () async {
    final dio = _FakeDio({
      ApiEndpoints.mobileSocial: {
        'token': 'social-token-1',
        'user': {
          'id': 7,
          'name': 'Sam',
          'email': 's@example.com',
          'avatar_url': null
        },
        'bands': <dynamic>[],
      },
    });

    final repo = AuthRepository(dio);
    final result =
        await repo.socialLogin('google', 'id-token-abc', 'tts_bandmate_app');

    expect(result.token, 'social-token-1');
    expect(result.user.id, 7);
    expect(dio.lastPostData, {
      'provider': 'google',
      'token': 'id-token-abc',
      'device_name': 'tts_bandmate_app',
    });
  });
}
