import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_bandmate/core/storage/route_storage.dart';
import 'package:tts_bandmate/core/storage/secure_storage.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/core/network/api_client.dart';
import 'package:tts_bandmate/features/bookings/data/bookings_cache_storage.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/features/chat/providers/topic_thread_provider.dart';

import 'helpers/test_harness.dart' show StubAdapter, json;

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late RouteStorage fakeRouteStorage;
  late BookingsCacheStorage fakeBookingsCache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    fakeRouteStorage = RouteStorage(prefs);
    fakeBookingsCache = BookingsCacheStorage(prefs);
  });

  group('AuthNotifier', () {
    /// Helper that builds a ProviderContainer wired to [FakeSecureStorage],
    /// an [ApiClient] that will never reach a real server, and a
    /// [routeStorageProvider] backed by mock SharedPreferences.
    ProviderContainer makeContainer(FakeSecureStorage storage) {
      return ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(storage: storage),
          ),
          routeStorageProvider.overrideWith(
            (ref) async => fakeRouteStorage,
          ),
          bookingsCacheStorageProvider.overrideWithValue(fakeBookingsCache),
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

        // Write a last-route to verify it is cleared on logout.
        fakeRouteStorage.writeLastRoute('/bookings/42');

        // Seed the bookings disk cache to verify it is dropped on logout.
        fakeBookingsCache.write(BookingsWindowCache(
          from: DateTime(2026, 2, 1),
          to: DateTime(2027, 2, 28),
          cachedAt: DateTime(2026, 5, 15),
          rawBookings: const [
            {'id': 1, 'name': 'Gala', 'date': '2026-06-01'},
          ],
        ));

        await container.read(authProvider.notifier).logout();

        final finalState = container.read(authProvider).value;
        expect(finalState, isA<AuthUnauthenticated>());
        expect(await storage.readToken(), isNull,
            reason: 'Token must be wiped on logout');
        expect(await storage.readBandId(), isNull,
            reason: 'Band ID must be wiped on logout');
        expect(await storage.readUser(), isNull,
            reason: 'Cached user must be wiped on logout');
        expect(fakeRouteStorage.readLastRoute(), isNull,
            reason: 'Last route must be cleared on logout');
        expect(fakeBookingsCache.read(), isNull,
            reason: 'Bookings disk cache must be cleared on logout');
      },
    );

    test(
      'test_logout_invalidates_chat_caches_so_a_new_user_does_not_see_the_'
      'previous_users_conversations',
      () async {
        // A repository whose responses are keyed on how many times each
        // endpoint has been hit — simulates "user A's data" the first time,
        // then a distinct payload on any refetch after logout invalidates
        // the providers (a real re-login would hit the server as a different
        // user; here we just need to prove the stale value isn't reused).
        var conversationsCalls = 0;
        var topicCalls = 0;
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
          ..httpClientAdapter = StubAdapter((options) async {
            if (options.path == '/api/mobile/conversations') {
              conversationsCalls++;
              return json(200, {
                'conversations': [
                  {
                    'id': 1,
                    'type': 'dm',
                    'title': conversationsCalls == 1 ? 'User A\'s DM' : 'refetched',
                    'unread_count': 0,
                  },
                ],
              });
            }
            // topicThread (events/rehearsals/bookings conversation) path.
            topicCalls++;
            return json(200, {
              'conversation': {
                'id': 2,
                'type': 'topic',
                'title': 'topic',
                'unread_count': 0,
              },
              'messages': <dynamic>[],
              'participants': <dynamic>[],
              'channel': '',
              'has_more': false,
            });
          });

        final storage = FakeSecureStorage();
        await storage.writeToken('some-valid-token');

        final container = ProviderContainer(overrides: [
          secureStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWith((ref) => ApiClient(storage: storage)),
          routeStorageProvider.overrideWith((ref) async => fakeRouteStorage),
          bookingsCacheStorageProvider.overrideWithValue(fakeBookingsCache),
          chatRepositoryProvider.overrideWithValue(ChatRepository(dio)),
        ]);
        addTearDown(container.dispose);

        container.read(authProvider.notifier).state = AsyncValue.data(
          AuthAuthenticated(user: _fakeUser, bands: _fakeBands),
        );

        const topic = TopicRef(kind: 'events', idOrKey: 'abc123');

        // Seed both chat caches with "user A"'s data, keeping them alive with
        // listeners the way a live Messages screen / CommentsSection would.
        final convSub = container.listen(chatConversationsProvider, (_, __) {});
        final topicSub = container.listen(topicThreadProvider(topic), (_, __) {});
        addTearDown(convSub.close);
        addTearDown(topicSub.close);

        final seededConversations =
            await container.read(chatConversationsProvider.future);
        expect(seededConversations.single.title, 'User A\'s DM');
        await container.read(topicThreadProvider(topic).future);
        expect(conversationsCalls, 1);
        expect(topicCalls, 1);

        await container.read(authProvider.notifier).logout();

        // Both providers must have been invalidated by logout — reading their
        // futures again must refetch (never warm-paint the disposed-user
        // cached value) rather than resolve instantly from stale state.
        final afterLogoutConversations =
            await container.read(chatConversationsProvider.future);
        await container.read(topicThreadProvider(topic).future);
        expect(conversationsCalls, 2,
            reason: 'chatConversationsProvider must refetch after logout');
        expect(topicCalls, 2,
            reason: 'topicThreadProvider must refetch after logout');
        expect(afterLogoutConversations.single.title, 'refetched');
      },
    );
  });
}
