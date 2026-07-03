import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/features/auth/data/social_sign_in_service.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/providers/social_sign_in_provider.dart';

import '../../helpers/test_harness.dart' show FakeSecureStorage;

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
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
            statusCode: 422, requestOptions: RequestOptions(path: path)),
      );
    }
    return Response<T>(
        data: body as T,
        statusCode: 200,
        requestOptions: RequestOptions(path: path));
  }
}

class _FakeApiClient extends Fake implements ApiClient {
  _FakeApiClient(this.dio);
  @override
  final Dio dio;
}

class _FakeSocialSignIn implements SocialSignInService {
  _FakeSocialSignIn(this.credential);
  final SocialCredential? credential;

  @override
  Future<SocialCredential?> signIn(SocialProvider provider) async =>
      credential;
}

void main() {
  const envelope = {
    'token': 't-1',
    'user': {'id': 1, 'name': 'S', 'email': 's@e.com', 'avatar_url': null},
    'bands': <dynamic>[],
  };

  ProviderContainer makeContainer({
    required SocialCredential? credential,
    Map<String, dynamic> responses = const {ApiEndpoints.mobileSocial: envelope},
  }) {
    return ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(_FakeApiClient(_FakeDio(responses))),
      socialSignInServiceProvider
          .overrideWithValue(_FakeSocialSignIn(credential)),
      secureStorageProvider.overrideWithValue(FakeSecureStorage()),
    ]);
  }

  test('successful social login transitions to AuthAuthenticated', () async {
    final container = makeContainer(
      credential: const SocialCredential(
          provider: SocialProvider.google, token: 'id-tok'),
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await container.read(authProvider.notifier).socialLogin(
          SocialProvider.google,
        );

    expect(container.read(authProvider).value, isA<AuthAuthenticated>());
  });

  test('cancelled native sheet leaves state untouched', () async {
    final container = makeContainer(credential: null);
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    final before = container.read(authProvider).value;

    await container.read(authProvider.notifier).socialLogin(
          SocialProvider.apple,
        );

    expect(container.read(authProvider).value, same(before));
  });

  test('backend rejection surfaces a friendly error', () async {
    final container = makeContainer(
      credential: const SocialCredential(
          provider: SocialProvider.google, token: 'bad'),
      responses: const {}, // 422 from fake dio
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);

    await container.read(authProvider.notifier).socialLogin(
          SocialProvider.google,
        );

    final state = container.read(authProvider).value;
    expect(state, isA<AuthUnauthenticated>());
    expect((state as AuthUnauthenticated).errorMessage, contains('Google'));
  });
}
