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
import 'package:tts_bandmate/features/bookings/widgets/create_booking_sheet.dart';

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

Future<Widget> _wrap({
  required Widget child,
  required AuthState auth,
  required Dio dio,
  required _FakeSecureStorage storage,
}) async {
  SharedPreferences.setMockInitialValues({});
  final routeStorage = RouteStorage(await SharedPreferences.getInstance());
  return ProviderScope(
    overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(_StubApiClient(storage: storage, dio: dio)),
      routeStorageProvider.overrideWith((_) async => routeStorage),
      authProvider.overrideWith(() => _FixedAuthNotifier(auth)),
    ],
    child: CupertinoApp(home: CupertinoPageScaffold(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders real bands and Personal gig row', (tester) async {
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: (_) {}),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [
          BandSummary(id: 10, name: 'The Real Band', isOwner: true),
          BandSummary(id: 11, name: 'Side Project', isOwner: false),
        ],
      ),
      dio: Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _StubAdapter((_) async => _json(200, {})),
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('The Real Band'), findsOneWidget);
    expect(find.text('Side Project'), findsOneWidget);
    expect(find.text('Personal gig'), findsOneWidget);
  });

  testWidgets('hides real-bands section when user has no real bands', (tester) async {
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: (_) {}),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [
          BandSummary(id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true),
        ],
      ),
      dio: Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _StubAdapter((_) async => _json(200, {})),
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Personal gig'), findsOneWidget);
    expect(find.text("Eddie's Band"), findsNothing,
        reason: 'Personal band should not be listed as a real band');
  });

  testWidgets('hides personal band from real-bands section', (tester) async {
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: (_) {}),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [
          BandSummary(id: 10, name: 'The Real Band', isOwner: true),
          BandSummary(id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true),
        ],
      ),
      dio: Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _StubAdapter((_) async => _json(200, {})),
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('The Real Band'), findsOneWidget);
    expect(find.text("Eddie's Band"), findsNothing);
    expect(find.text('Personal gig'), findsOneWidget);
  });

  testWidgets('tapping a real band invokes callback with that band id', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: selected.add),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [BandSummary(id: 10, name: 'The Real Band', isOwner: true)],
      ),
      dio: Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _StubAdapter((_) async => _json(200, {})),
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Real Band'));
    await tester.pumpAndSettle();
    expect(selected, equals([10]));
  });

  testWidgets('tapping Personal gig with existing personal band invokes callback immediately',
      (tester) async {
    final selected = <int>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((_) async => fail('Should not call API'));
    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: selected.add),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [
          BandSummary(id: 10, name: 'Real', isOwner: true),
          BandSummary(id: 99, name: "Eddie's Band", isOwner: true, isPersonal: true),
        ],
      ),
      dio: dio,
      storage: _FakeSecureStorage(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal gig'));
    await tester.pumpAndSettle();
    expect(selected, equals([99]));
  });

  testWidgets('tapping Personal gig with no personal band creates one then invokes callback',
      (tester) async {
    final selected = <int>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async {
        if (req.path == '/api/mobile/bands/solo' && req.method == 'POST') {
          return _json(201, {
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        if (req.path == '/api/mobile/auth/me' && req.method == 'GET') {
          return _json(200, {
            'user': {'id': 1, 'name': 'Eddie', 'email': 'e@e.com', 'avatar_url': null},
            'bands': [
              {'id': 10, 'name': 'Real', 'is_owner': true, 'is_personal': false},
              {'id': 99, 'name': "Eddie's Band", 'is_owner': true, 'is_personal': true},
            ],
          });
        }
        return _json(404, {});
      });
    final storage = _FakeSecureStorage();
    await storage.writeToken('t');

    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: selected.add),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
      dio: dio,
      storage: storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal gig'));
    await tester.pumpAndSettle();

    expect(selected, equals([99]));
  });

  testWidgets('tapping Personal gig on API failure shows inline error', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = _StubAdapter((req) async => _json(500, {'message': 'fire'}));

    final storage = _FakeSecureStorage();
    await storage.writeToken('t');

    await tester.pumpWidget(await _wrap(
      child: CreateBookingSheet(onBandSelected: (_) {}),
      auth: const AuthAuthenticated(
        user: AuthUser(id: 1, name: 'Eddie', email: 'e@e.com'),
        bands: [BandSummary(id: 10, name: 'Real', isOwner: true)],
      ),
      dio: dio,
      storage: storage,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal gig'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Try again'), findsOneWidget);
  });
}
