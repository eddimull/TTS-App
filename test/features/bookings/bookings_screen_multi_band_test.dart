import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/providers/core_providers.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/bookings/screens/bookings_screen.dart';

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

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override Future<AuthState> build() async => _fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bookings screen lists bookings across multiple bands with chips',
      (tester) async {
    // Use a large logical surface so the SliverPersistentHeader has enough
    // paint extent to satisfy the layout assertion in debug mode.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final routeStorage = RouteStorage(await SharedPreferences.getInstance());
    final storage = _FakeSecureStorage();
    await storage.writeToken('t');

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        if (req.path == '/api/mobile/me/bookings') {
          return _json(200, {
            'bookings': [
              {
                'id': 1,
                'name': 'Big Show',
                'date': '${DateTime.now().year}-06-01',
                'is_paid': false,
                'contacts': [],
                'status': 'confirmed',
                'band': {
                  'id': 10,
                  'name': 'The Rocking Eds',
                  'is_owner': true,
                  'is_personal': false,
                  'logo_url': null,
                },
              },
              {
                'id': 2,
                'name': 'Sunday Service',
                'date': '${DateTime.now().year}-06-02',
                'is_paid': false,
                'contacts': [],
                'status': 'confirmed',
                'band': {
                  'id': 99,
                  'name': "Eddie's Band",
                  'is_owner': true,
                  'is_personal': true,
                  'logo_url': null,
                },
              },
            ],
          });
        }
        return _json(404, {});
      });

    final widget = ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        apiClientProvider
            .overrideWithValue(_StubApiClient(storage: storage, dio: dio)),
        routeStorageProvider.overrideWith((_) async => routeStorage),
        authProvider.overrideWith(() => _FixedAuthNotifier(const AuthAuthenticated(
              user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
              bands: [
                BandSummary(id: 10, name: 'The Rocking Eds', isOwner: true),
              ],
            ))),
      ],
      child: const CupertinoApp(home: BookingsScreen()),
    );

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('Big Show'), findsOneWidget);
    expect(find.text('Sunday Service'), findsOneWidget);
    expect(find.text('The Rocking Eds'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
  });
}
