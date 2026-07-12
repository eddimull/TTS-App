import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/pusher_connection.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/chat/providers/conversations_provider.dart';
import 'package:tts_bandmate/shared/providers/band_realtime_provider.dart';
import 'package:tts_bandmate/shared/providers/user_realtime_provider.dart';

class FakeAuth extends AuthNotifier {
  FakeAuth(this._state);
  final AuthState _state;

  @override
  Future<AuthState> build() async => _state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> subscribedChannels;
  late PusherJsonHandler? capturedHandler;
  late List<ProviderOrFamily> invalidated;

  ProviderContainer makeContainer(AuthState authState) {
    subscribedChannels = [];
    capturedHandler = null;
    invalidated = [];
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(() => FakeAuth(authState)),
      bandRealtimeDebounceProvider.overrideWithValue(Duration.zero),
      providerInvalidatorProvider.overrideWithValue((p) => invalidated.add(p)),
      userChannelBinderProvider.overrideWithValue((channel, onEvent) async {
        subscribedChannels.add(channel);
        capturedHandler = onEvent;
        return () async {};
      }),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  AuthState authedAs(int userId) => AuthAuthenticated(
        user: AuthUser(id: userId, name: 'Eddie', email: 'e@x.com'),
        bands: const [],
      );

  Future<void> activate(ProviderContainer c) async {
    c.read(userRealtimeProvider);
    await c.read(authProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  test('subscribes to the authed user channel', () async {
    final c = makeContainer(authedAs(42));
    await activate(c);
    expect(subscribedChannels, ['private-App.Models.User.42']);
    expect(c.read(userRealtimeProvider), 42);
  });

  test('does not subscribe when unauthenticated', () async {
    final c = makeContainer(const AuthUnauthenticated());
    await activate(c);
    expect(subscribedChannels, isEmpty);
  });

  test('message signal invalidates the conversation list', () async {
    final c = makeContainer(authedAs(42));
    await activate(c);
    capturedHandler!('user.data-changed',
        {'model': 'message', 'id': 9, 'action': 'created'});
    await Future<void>.delayed(Duration.zero);
    expect(invalidated, contains(chatConversationsProvider));
  });
}
