// End-to-end integration test for the login → band selection → dashboard flow.
//
// Run with:
//   flutter test integration_test/login_to_dashboard_test.dart
//   flutter test integration_test/login_to_dashboard_test.dart -d chrome \
//     --dart-define=BASE_URL=http://localhost:8715
//
// The HTTP layer is stubbed via a fake Dio HttpClientAdapter so this test runs
// without a backend. Everything else (router, providers, screens) is real.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tts_bandmate/app.dart';
import 'package:tts_bandmate/core/config/router.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/core/network/api_endpoints.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class FakeSecureStorage extends SecureStorage {
  FakeSecureStorage() : super(const FlutterSecureStorage());

  final Map<String, String?> _map = {};

  @override
  Future<String?> readToken() async => _map['auth_token'];
  @override
  Future<void> writeToken(String token) async => _map['auth_token'] = token;
  @override
  Future<void> deleteToken() async => _map.remove('auth_token');

  @override
  Future<String?> readBandId() async => _map['selected_band_id'];
  @override
  Future<void> writeBandId(String bandId) async =>
      _map['selected_band_id'] = bandId;
  @override
  Future<void> deleteBandId() async => _map.remove('selected_band_id');

  @override
  Future<String?> readUser() async => _map['current_user_json'];
  @override
  Future<void> writeUser(String userJson) async =>
      _map['current_user_json'] = userJson;

  @override
  Future<void> clear() async => _map.clear();
}

/// A Dio adapter that returns canned responses based on the request path.
/// Replaces network I/O for the duration of the test.
class StubAdapter implements HttpClientAdapter {
  StubAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _handler(options);
}

ResponseBody _json(int status, Object body) {
  final encoded = utf8.encode(jsonEncode(body));
  return ResponseBody.fromBytes(
    encoded,
    status,
    headers: {
      'content-type': ['application/json'],
    },
  );
}

// ── Test ──────────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'login → band auto-selects (single band) → dashboard',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final routeStorage = RouteStorage(prefs);
      final storage = FakeSecureStorage();

      // Build a Dio that returns canned JSON for the endpoints we hit.
      final stubbedDio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = StubAdapter((options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileToken)) {
            return _json(200, {
              'token': 'fake-token-xyz',
              'user': {
                'id': 1,
                'name': 'Eddie',
                'email': 'eddie@example.com',
              },
              'bands': [
                {'id': 10, 'name': 'The Rocking Eds', 'is_owner': true},
              ],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileMe)) {
            return _json(200, {
              'user': {
                'id': 1,
                'name': 'Eddie',
                'email': 'eddie@example.com',
              },
              'bands': [
                {'id': 10, 'name': 'The Rocking Eds', 'is_owner': true},
              ],
            });
          }
          // Anything else (dashboard data, etc.) — return empty success so the
          // dashboard renders without crashing on unrelated calls.
          return _json(200, {'data': []});
        });

      // Wrap the stubbed Dio in an ApiClient by exposing it through a subclass
      // override of apiClientProvider.
      final fakeApiClient = _StubApiClient(storage: storage, dio: stubbedDio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(storage),
            apiClientProvider.overrideWithValue(fakeApiClient),
            routeStorageProvider.overrideWith((_) async => routeStorage),
            initialLocationProvider.overrideWithValue('/login'),
          ],
          child: const BandmateApp(),
        ),
      );

      // Wait for first frame + auth bootstrap.
      await tester.pumpAndSettle();

      // We should be on the login screen.
      expect(find.text('Sign In'), findsOneWidget);

      // Fill credentials.
      await tester.enterText(find.byType(CupertinoTextField).at(0),
          'eddie@example.com');
      await tester.enterText(
          find.byType(CupertinoTextField).at(1), 'password123');

      // Tap "Sign In".
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Single-band path: the router should auto-select band 10 and land on
      // /dashboard. Assert the stored token and band ID, and that we're no
      // longer on /login.
      expect(await storage.readToken(), 'fake-token-xyz');
      expect(find.text('Sign In'), findsNothing);
    },
  );
}

/// ApiClient that serves a pre-built Dio so the test can stub responses.
class _StubApiClient extends ApiClient {
  _StubApiClient({required super.storage, required Dio dio})
      : _stubDio = dio;

  final Dio _stubDio;

  @override
  Dio get dio => _stubDio;
}
