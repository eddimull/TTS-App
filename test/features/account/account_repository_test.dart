import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/account/data/account_repository.dart';

// Minimal Dio fake — records the last patch/delete and returns canned GET data.
class _FakeDio extends Fake implements Dio {
  _FakeDio(this._responses);

  final Map<String, dynamic> _responses;
  String? lastPatchPath;
  Map<String, dynamic>? lastPatchData;
  bool deleteCalled = false;
  String? lastDeletePath;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
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

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
    void Function(int, int)? onSendProgress,
  }) async {
    lastPatchPath = path;
    lastPatchData = data as Map<String, dynamic>?;
    return Response<T>(
      data: _responses['__patch__'] as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    deleteCalled = true;
    lastDeletePath = path;
    return Response<T>(
      data: null,
      statusCode: 202,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  const accountPath = '/api/mobile/account';

  Map<String, dynamic> accountPayload() => {
        accountPath: {
          'account': {
            'id': 7,
            'name': 'Jane Player',
            'email': 'jane@example.com',
            'address1': '1 Main St',
            'address2': null,
            'city': 'Baton Rouge',
            'state_id': '12',
            'country_id': '1',
            'zip': '70801',
            'email_notifications': true,
          },
          'states': [
            {'state_id': 12, 'state_name': 'Louisiana', 'country_id': 1},
            {'state_id': 5, 'state_name': 'California', 'country_id': 1},
          ],
          'countries': [
            {'id': 1, 'country_name': 'United States'},
          ],
        },
        '__patch__': {
          'account': {
            'id': 7,
            'name': 'New Name',
            'email': 'jane@example.com',
            'email_notifications': false,
          },
        },
      };

  group('AccountRepository', () {
    test('getAccount parses profile and lookup lists', () async {
      final repo = AccountRepository(_FakeDio(accountPayload()));
      final result = await repo.getAccount();

      expect(result.profile.name, 'Jane Player');
      expect(result.profile.stateId, '12');
      expect(result.profile.emailNotifications, isTrue);
      expect(result.states.length, 2);
      expect(result.states.first.name, 'Louisiana');
      expect(result.states.first.countryId, '1');
      expect(result.countries.single.name, 'United States');
    });

    test('updateAccount omits password when blank', () async {
      final dio = _FakeDio(accountPayload());
      final repo = AccountRepository(dio);

      await repo.updateAccount(
        name: 'New Name',
        email: 'jane@example.com',
        password: '',
        emailNotifications: false,
      );

      expect(dio.lastPatchPath, accountPath);
      expect(dio.lastPatchData!.containsKey('password'), isFalse);
      expect(dio.lastPatchData!.containsKey('password_confirmation'), isFalse);
      expect(dio.lastPatchData!['email_notifications'], isFalse);
    });

    test('updateAccount includes password + confirmation when set', () async {
      final dio = _FakeDio(accountPayload());
      final repo = AccountRepository(dio);

      await repo.updateAccount(
        name: 'New Name',
        email: 'jane@example.com',
        password: 'super-secret',
        emailNotifications: true,
      );

      expect(dio.lastPatchData!['password'], 'super-secret');
      expect(dio.lastPatchData!['password_confirmation'], 'super-secret');
    });

    test('requestDeletion issues a DELETE', () async {
      final dio = _FakeDio(accountPayload());
      final repo = AccountRepository(dio);

      await repo.requestDeletion();

      expect(dio.deleteCalled, isTrue);
      expect(dio.lastDeletePath, accountPath);
    });
  });
}
