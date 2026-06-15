import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';

class _FakeSecureStorage extends SecureStorage {
  _FakeSecureStorage() : super(const FlutterSecureStorage());
  final Map<String, String?> _m = {};
  @override
  Future<String?> readToken() async => _m['t'];
  @override
  Future<void> writeToken(String t) async => _m['t'] = t;
  @override
  Future<void> deleteToken() async => _m.remove('t');
  @override
  Future<String?> readBandId() async => _m['b'];
  @override
  Future<void> writeBandId(String id) async => _m['b'] = id;
  @override
  Future<void> deleteBandId() async => _m.remove('b');
  @override
  Future<String?> readUser() async => _m['u'];
  @override
  Future<void> writeUser(String u) async => _m['u'] = u;
  @override
  Future<void> clear() async => _m.clear();
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) =>
      handler(o);
}

ResponseBody _json(int s, Object b) =>
    ResponseBody.fromBytes(utf8.encode(jsonEncode(b)), s, headers: {
      'content-type': ['application/json'],
    });

const _validRefreshUser = {
  'id': 1,
  'name': 'Eddie',
  'email': 'e@e.com',
  'avatar_url': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'refreshes once and retries once on Insufficient token permissions 403',
      () async {
    final storage = _FakeSecureStorage();
    await storage.writeToken('stale-token');

    var protectedCalls = 0;
    var refreshCalls = 0;

    final client = ApiClient(storage: storage);
    client.dio.httpClientAdapter = _StubAdapter((req) async {
      if (req.path == ApiEndpoints.mobileTokenRefresh) {
        refreshCalls++;
        return _json(200, {
          'token': 'fresh-token',
          'user': _validRefreshUser,
          'bands': <dynamic>[],
        });
      }
      if (req.path == '/protected') {
        protectedCalls++;
        if (protectedCalls == 1) {
          return _json(403, {'message': 'Insufficient token permissions.'});
        }
        return _json(200, {'ok': true});
      }
      return _json(404, {'message': 'unexpected ${req.method} ${req.path}'});
    });

    final response = await client.dio.get<dynamic>('/protected');

    expect(response.statusCode, 200);
    expect((response.data as Map)['ok'], isTrue);
    expect(await storage.readToken(), 'fresh-token',
        reason: 'refresh should have persisted the new token');
    expect(refreshCalls, 1, reason: 'refresh should be called exactly once');
    expect(protectedCalls, 2,
        reason: 'protected path hit twice: original + one retry');
  });

  test('does not refresh on other 403 messages', () async {
    final storage = _FakeSecureStorage();
    await storage.writeToken('stale-token');

    var refreshCalled = false;

    final client = ApiClient(storage: storage);
    client.dio.httpClientAdapter = _StubAdapter((req) async {
      if (req.path == ApiEndpoints.mobileTokenRefresh) {
        refreshCalled = true;
        return _json(200, {
          'token': 'fresh-token',
          'user': _validRefreshUser,
          'bands': <dynamic>[],
        });
      }
      if (req.path == '/protected') {
        return _json(403, {'message': 'You are not a member of this band.'});
      }
      return _json(404, {'message': 'unexpected ${req.method} ${req.path}'});
    });

    await expectLater(
      client.dio.get<dynamic>('/protected'),
      throwsA(isA<DioException>()),
    );

    expect(refreshCalled, isFalse,
        reason: 'refresh must not fire for unrelated 403 messages');
    expect(await storage.readToken(), 'stale-token',
        reason: 'token must remain unchanged');
  });
}
