import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/network/api_response_cache.dart';
import 'package:tts_bandmate/core/network/network_failure.dart';
import 'package:tts_bandmate/core/network/offline_interceptor.dart';
import 'package:tts_bandmate/core/network/reachability.dart';
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
  Future<String?> readBands() async => _m['bands'];
  @override
  Future<void> writeBands(String b) async => _m['bands'] = b;
  @override
  Future<void> clear() async => _m.clear();
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  int calls = 0;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) {
    calls++;
    return handler(o);
  }
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromBytes(utf8.encode(jsonEncode(body)), status, headers: {
      'content-type': ['application/json'],
    });

Never _networkDown(RequestOptions options) {
  throw DioException.connectionError(
    requestOptions: options,
    reason: 'Failed host lookup',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Reachability reachability;
  late DateTime now;
  late SharedPreferences prefs;

  setUp(() async {
    now = DateTime(2026, 1, 1, 12);
    reachability = Reachability(
      retryAfter: const Duration(seconds: 5),
      clock: () => now,
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ApiClient buildClient({ApiResponseCache? cache, String? bandId}) => ApiClient(
        storage: _FakeSecureStorage(),
        bandId: bandId,
        reachability: reachability,
        cache: cache,
      );

  group('fail fast', () {
    test('a second request after a transport failure never hits the wire',
        () async {
      final client = buildClient();
      final adapter = _StubAdapter((o) async => _networkDown(o));
      client.dio.httpClientAdapter = adapter;

      await expectLater(
        client.dio.get<dynamic>('/api/mobile/dashboard'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls, 1);

      final second = await client.dio
          .get<dynamic>('/api/mobile/dashboard')
          .then<Object?>((r) => r)
          .catchError((Object e) => e);

      expect(adapter.calls, 1,
          reason: 'the client already knew the server was unreachable');
      expect(isOfflineShortCircuit(second), isTrue);
      expect(isNetworkFailure(second), isTrue);
    });

    test('lets one request through again once the backoff has elapsed',
        () async {
      final client = buildClient();
      final adapter = _StubAdapter((o) async => _networkDown(o));
      client.dio.httpClientAdapter = adapter;

      await expectLater(
        client.dio.get<dynamic>('/ping'),
        throwsA(isA<DioException>()),
      );

      now = now.add(const Duration(seconds: 6));

      await expectLater(
        client.dio.get<dynamic>('/ping'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.calls, 2);
    });

    test('a server error does not open the circuit', () async {
      final client = buildClient();
      client.dio.httpClientAdapter =
          _StubAdapter((_) async => _json(500, {'message': 'boom'}));

      await expectLater(
        client.dio.get<dynamic>('/api/mobile/dashboard'),
        throwsA(isA<DioException>()),
      );

      expect(reachability.isOnline, isTrue,
          reason: 'a 500 proves the server answered');
      expect(reachability.shouldShortCircuit(), isFalse);
    });
  });

  group('offline cache', () {
    test('replays the last successful GET when the network is down', () async {
      final cache = ApiResponseCache(prefs);
      final client = buildClient(cache: cache, bandId: '7');

      var online = true;
      client.dio.httpClientAdapter = _StubAdapter((o) async {
        if (!online) _networkDown(o);
        return _json(200, {
          'events': [
            {'id': 1, 'name': 'Gig'},
          ],
        });
      });

      final live = await client.dio.get<Map<String, dynamic>>(
        '/api/mobile/dashboard',
      );
      expect((live.data!['events'] as List), hasLength(1));

      online = false;

      final offline = await client.dio.get<Map<String, dynamic>>(
        '/api/mobile/dashboard',
      );

      expect((offline.data!['events'] as List).single, {
        'id': 1,
        'name': 'Gig',
      });
      expect(offline.requestOptions.extra[kFromCacheKey], isTrue);
      expect(offline.requestOptions.extra[kCachedAtKey], isA<int>());
      expect(reachability.isOffline, isTrue,
          reason: 'serving from cache must not hide the offline state');
    });

    test('a short-circuited GET is served from cache too', () async {
      final cache = ApiResponseCache(prefs);
      final client = buildClient(cache: cache, bandId: '7');

      var online = true;
      final adapter = _StubAdapter((o) async {
        if (!online) _networkDown(o);
        return _json(200, {'ok': true});
      });
      client.dio.httpClientAdapter = adapter;

      await client.dio.get<Map<String, dynamic>>('/api/mobile/songs');

      online = false;
      await expectLater(
        client.dio.get<dynamic>('/api/mobile/other'),
        throwsA(isA<DioException>()),
      );
      final callsBefore = adapter.calls;

      final cached = await client.dio.get<Map<String, dynamic>>(
        '/api/mobile/songs',
      );

      expect(cached.data, {'ok': true});
      expect(adapter.calls, callsBefore,
          reason: 'answered from disk without touching the network');
    });

    test('a different band is not served the previous band’s data', () async {
      final cache = ApiResponseCache(prefs);

      final bandSeven = buildClient(cache: cache, bandId: '7');
      bandSeven.dio.httpClientAdapter =
          _StubAdapter((_) async => _json(200, {'band': 7}));
      await bandSeven.dio.get<Map<String, dynamic>>('/api/mobile/dashboard');

      final bandEight = buildClient(cache: cache, bandId: '8');
      bandEight.dio.httpClientAdapter =
          _StubAdapter((o) async => _networkDown(o));

      await expectLater(
        bandEight.dio.get<dynamic>('/api/mobile/dashboard'),
        throwsA(isA<DioException>()),
      );
    });

    test('never replays a write', () async {
      final cache = ApiResponseCache(prefs);
      final client = buildClient(cache: cache);

      var online = true;
      client.dio.httpClientAdapter = _StubAdapter((o) async {
        if (!online) _networkDown(o);
        return _json(200, {'created': true});
      });

      await client.dio.post<dynamic>('/api/mobile/bookings');

      online = false;

      await expectLater(
        client.dio.post<dynamic>('/api/mobile/bookings'),
        throwsA(isA<DioException>()),
        reason: 'a write that never reached the server must surface as one',
      );
    });

    test('does not cache the session endpoints', () async {
      final cache = ApiResponseCache(prefs);
      final client = buildClient(cache: cache);

      client.dio.httpClientAdapter =
          _StubAdapter((_) async => _json(200, {'user': 'Eddie'}));
      await client.dio.get<Map<String, dynamic>>('/api/mobile/auth/me');

      expect(cache.entryCount, 0,
          reason: 'the session lives in SecureStorage, not in plaintext prefs');
    });
  });

  group('recovery', () {
    test('a successful request closes the circuit', () async {
      final client = buildClient();

      var online = false;
      client.dio.httpClientAdapter = _StubAdapter((o) async {
        if (!online) _networkDown(o);
        return _json(200, {'ok': true});
      });

      await expectLater(
        client.dio.get<dynamic>('/ping'),
        throwsA(isA<DioException>()),
      );
      expect(reachability.isOffline, isTrue);

      online = true;
      now = now.add(const Duration(seconds: 6));
      await client.dio.get<dynamic>('/ping');

      expect(reachability.isOnline, isTrue);
      expect(reachability.shouldShortCircuit(), isFalse);
    });

    test('the reachability probe bypasses the open circuit', () async {
      final client = buildClient();
      final adapter = _StubAdapter(
        (_) async => ResponseBody.fromString('', 200, headers: {
          'content-type': ['text/html'],
        }),
      );
      client.dio.httpClientAdapter = adapter;

      reachability.recordFailure();
      expect(reachability.shouldShortCircuit(), isTrue);

      await client.probeReachability();

      expect(adapter.calls, 1,
          reason: 'the probe is the exception to fail-fast');
      expect(reachability.isOnline, isTrue);
    });
  });
}
