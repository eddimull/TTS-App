import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';
import 'package:tts_bandmate/features/bands/data/bands_repository.dart';

// In-memory SecureStorage fake — mirrors _FakeSecureStorage in
// test/providers/personal_band_provider_test.dart.
class _FakeSecureStorage extends SecureStorage {
  _FakeSecureStorage() : super(const FlutterSecureStorage());
  final Map<String, String?> _m = {};
  @override Future<String?> readToken() async => _m['t'];
  @override Future<void> writeToken(String t) async => _m['t'] = t;
  @override Future<void> deleteToken() async => _m.remove('t');
  @override Future<String?> readBandId() async => _m['b'];
  @override Future<void> writeBandId(String id) async => _m['b'] = id;
  @override Future<void> deleteBandId() async => _m.remove('b');
  @override Future<String?> readUser() async => _m['u'];
  @override Future<void> writeUser(String u) async => _m['u'] = u;
  @override Future<void> clear() async => _m.clear();
}

// Minimal Dio fake — mirrors the pattern in
// test/features/band_settings/band_settings_repository_test.dart.
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
    if (body == null) throw DioException(requestOptions: RequestOptions(path: path));
    return Response<T>(
      data: body as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }
}

void main() {
  group('BandsRepository.goSolo', () {
    test('persists token from response and returns parsed bands list', () async {
      final dio = _FakeDio({
        ApiEndpoints.mobileBandsSolo: {
          'token': 'solo-token-xyz',
          'bands': [
            {
              'id': 7,
              'name': "Wes's Band",
              'is_owner': true,
              'is_personal': true,
              'logo_url': null,
            },
          ],
        },
      });

      final storage = _FakeSecureStorage();
      final repo = BandsRepository(dio, storage);

      final bands = await repo.goSolo();

      // Token must be persisted.
      expect(await storage.readToken(), equals('solo-token-xyz'));

      // Returned list must be parsed correctly.
      expect(bands, hasLength(1));
      expect(bands.first.id, equals(7));
      expect(bands.first.name, equals("Wes's Band"));
      expect(bands.first.isPersonal, isTrue);
    });

    test('handles missing token gracefully (no token key in response)', () async {
      final dio = _FakeDio({
        ApiEndpoints.mobileBandsSolo: {
          // No 'token' key — backward-compat with older backend.
          'bands': [
            {
              'id': 7,
              'name': "Wes's Band",
              'is_owner': true,
              'is_personal': true,
              'logo_url': null,
            },
          ],
        },
      });

      final storage = _FakeSecureStorage();
      final repo = BandsRepository(dio, storage);

      final bands = await repo.goSolo();

      // Token should not be written when absent.
      expect(await storage.readToken(), isNull);

      // Bands still parsed.
      expect(bands.first.id, equals(7));
    });
  });
}
