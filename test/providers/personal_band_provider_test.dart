import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/shared/providers/personal_band_provider.dart';

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

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override void close({bool force = false}) {}
  @override Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      handler(o);
}

ResponseBody _json(int s, Object b) =>
    ResponseBody.fromBytes(utf8.encode(jsonEncode(b)), s, headers: {
      'content-type': ['application/json'],
    });

class _StubApiClient extends ApiClient {
  _StubApiClient({required super.storage, required Dio dio}) : _stub = dio;
  final Dio _stub;
  @override Dio get dio => _stub;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RouteStorage routeStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    routeStorage = RouteStorage(await SharedPreferences.getInstance());
  });

  ProviderContainer makeContainer({
    required _FakeSecureStorage storage,
    required Dio dio,
    required AuthState initialAuth,
  }) {
    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(_StubApiClient(storage: storage, dio: dio)),
      routeStorageProvider.overrideWith((_) async => routeStorage),
    ]);
    container.read(authProvider.notifier).state = AsyncValue.data(initialAuth);
    return container;
  }

  test('personalBand getter returns band when isPersonal==true exists in auth state', () {
    final personal = const BandSummary(
      id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((_) async => _json(200, {}));

    final container = makeContainer(
      storage: _FakeSecureStorage(),
      dio: dio,
      initialAuth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [
          const BandSummary(id: 10, name: 'Real', isOwner: true),
          personal,
        ],
      ),
    );
    addTearDown(container.dispose);

    final found = container.read(personalBandProvider.notifier).personalBand;
    expect(found, isNotNull);
    expect(found!.id, equals(99));
    expect(found.isPersonal, isTrue);
  });

  test('personalBand getter returns null when no personal band exists', () {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((_) async => _json(200, {}));

    final container = makeContainer(
      storage: _FakeSecureStorage(),
      dio: dio,
      initialAuth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
    );
    addTearDown(container.dispose);

    expect(container.read(personalBandProvider.notifier).personalBand, isNull);
  });

  test('ensureExists returns existing personal band without API call', () async {
    final personal = const BandSummary(
      id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((_) async => fail('Should not call API'));

    final container = makeContainer(
      storage: _FakeSecureStorage(),
      dio: dio,
      initialAuth: AuthAuthenticated(
        user: const AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [
          const BandSummary(id: 10, name: 'Real', isOwner: true),
          personal,
        ],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(personalBandProvider.notifier).ensureExists();

    expect(result.id, equals(99));
    expect(result.isPersonal, isTrue);
  });

  test('ensureExists creates personal band when missing and API succeeds', () async {
    int soloCalls = 0;
    int meCalls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        if (req.path == '/api/mobile/bands/solo' && req.method == 'POST') {
          soloCalls++;
          return _json(201, {
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        if (req.path == '/api/mobile/auth/me' && req.method == 'GET') {
          meCalls++;
          return _json(200, {
            'user': {'id': 1, 'name': 'Eddie', 'email': 'e@e.com', 'avatar_url': null},
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        return _json(404, {'message': 'unexpected ${req.method} ${req.path}'});
      });

    final storage = _FakeSecureStorage();
    await storage.writeToken('test-token');

    final container = makeContainer(
      storage: storage,
      dio: dio,
      initialAuth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
    );
    addTearDown(container.dispose);

    final result = await container.read(personalBandProvider.notifier).ensureExists();

    expect(soloCalls, equals(1));
    expect(meCalls, greaterThanOrEqualTo(1),
        reason: 'auth state should refresh after solo to pick up new band');
    expect(result.id, equals(99));
    expect(result.isPersonal, isTrue);

    final auth = container.read(authProvider).value;
    expect(auth, isA<AuthAuthenticated>());
    final updatedBands = (auth as AuthAuthenticated).bands;
    expect(updatedBands.any((b) => b.isPersonal), isTrue);
  });

  test('ensureExists propagates error and leaves state unchanged on API failure', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async => _json(500, {'message': 'fire'}));

    final storage = _FakeSecureStorage();
    await storage.writeToken('test-token');

    final container = makeContainer(
      storage: storage,
      dio: dio,
      initialAuth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(personalBandProvider.notifier).ensureExists(),
      throwsA(anything),
    );

    final auth = container.read(authProvider).value as AuthAuthenticated;
    expect(auth.bands, hasLength(1));
    expect(auth.bands.any((b) => b.isPersonal), isFalse);
  });
}
