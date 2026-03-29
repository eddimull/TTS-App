import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/core/network/api_client.dart';

// ── In-memory fake storage ────────────────────────────────────────────────────

/// An in-memory [SecureStorage] substitute for unit tests.
/// Bypasses [FlutterSecureStorage] entirely via the map-backed overrides.
class FakeSecureStorage extends SecureStorage {
  // Pass any FlutterSecureStorage to satisfy the super constructor — it is
  // never called because every method is overridden below.
  FakeSecureStorage()
      : super(const FlutterSecureStorage());

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

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _fakeUser = AuthUser(id: 1, name: 'Eddie', email: 'eddie@example.com');
final _fakeBands = [
  const BandSummary(id: 10, name: 'The Rocking Eds', isOwner: true),
  const BandSummary(id: 11, name: 'Side Project', isOwner: false),
];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AuthNotifier', () {
    /// Helper that builds a ProviderContainer wired to [FakeSecureStorage] and
    /// an [ApiClient] that will never be able to reach a real server.
    ProviderContainer makeContainer(FakeSecureStorage storage) {
      return ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(storage: storage),
          ),
        ],
      );
    }

    test(
      'test_build_returns_unauthenticated_when_no_token_in_storage',
      () async {
        final storage = FakeSecureStorage();
        // No token written — build() should return AuthUnauthenticated without
        // ever attempting a network call.
        final container = makeContainer(storage);
        addTearDown(container.dispose);

        final state = await container.read(authProvider.future);

        expect(state, isA<AuthUnauthenticated>());
        expect((state as AuthUnauthenticated).errorMessage, isNull);
      },
    );

    test(
      'test_build_clears_token_and_returns_unauthenticated_when_getme_fails',
      () async {
        final storage = FakeSecureStorage();
        // Write a stale token — getMe() will fail (no real server).
        await storage.writeToken('stale-token-abc');

        final container = makeContainer(storage);
        addTearDown(container.dispose);

        final state = await container.read(authProvider.future);

        // The notifier should clear the bad token so the user is not stuck.
        expect(state, isA<AuthUnauthenticated>());
        expect(await storage.readToken(), isNull,
            reason: 'Stale token must be removed on getMe failure');
      },
    );

    test(
      'test_logout_clears_all_stored_credentials_and_returns_unauthenticated',
      () async {
        final storage = FakeSecureStorage();
        await storage.writeToken('some-valid-token');
        await storage.writeBandId('10');
        await storage.writeUser('{"id":1,"name":"Eddie","email":"e@e.com"}');

        final container = makeContainer(storage);
        addTearDown(container.dispose);

        // Let build() finish (it will clear the bad token and go unauthenticated).
        await container.read(authProvider.future);

        // Manually inject an authenticated state so we can test the logout path.
        container.read(authProvider.notifier).state = AsyncValue.data(
          AuthAuthenticated(user: _fakeUser, bands: _fakeBands),
        );

        await container.read(authProvider.notifier).logout();

        final finalState = container.read(authProvider).valueOrNull;
        expect(finalState, isA<AuthUnauthenticated>());
        expect(await storage.readToken(), isNull,
            reason: 'Token must be wiped on logout');
        expect(await storage.readBandId(), isNull,
            reason: 'Band ID must be wiped on logout');
        expect(await storage.readUser(), isNull,
            reason: 'Cached user must be wiped on logout');
      },
    );
  });
}
