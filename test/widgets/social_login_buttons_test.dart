import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/data/social_sign_in_service.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/widgets/social_login_buttons.dart';

// ── Fake AuthNotifier ─────────────────────────────────────────────────────────

const _fakeUser = AuthUser(id: 1, name: 'Eddie', email: 'eddie@example.com');

/// A notifier that lets each test script the outcome of socialLogin without
/// touching the network. Defaults to succeeding.
class FakeAuthNotifier extends AuthNotifier {
  bool socialLoginCalled = false;
  SocialProvider? lastProvider;

  /// If set, socialLogin ends in AuthUnauthenticated with this message
  /// instead of AuthAuthenticated.
  String? errorToReturn;

  @override
  Future<AuthState> build() async => const AuthUnauthenticated();

  @override
  Future<void> socialLogin(SocialProvider provider) async {
    socialLoginCalled = true;
    lastProvider = provider;
    state = errorToReturn != null
        ? AsyncValue.data(AuthUnauthenticated(errorMessage: errorToReturn))
        : const AsyncValue.data(
            AuthAuthenticated(user: _fakeUser, bands: []),
          );
  }
}

// ── Widget wrapper ────────────────────────────────────────────────────────────

/// Wraps SocialLoginButtons in a caller-supplied ProviderContainer (via
/// UncontrolledProviderScope) so tests can await `authProvider.future` on
/// that same container before interacting. Without this, the
/// AsyncNotifier's pending initial build() can resolve *after* a
/// manually-set state change (e.g. from a fake's socialLogin) and clobber it
/// back to the build() default — see auth_notifier_social_test.dart, which
/// awaits the same future for the same reason.
Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const CupertinoApp(
      home: CupertinoPageScaffold(
        child: Center(child: SocialLoginButtons()),
      ),
    ),
  );
}

ProviderContainer _containerFor(FakeAuthNotifier notifier) {
  return ProviderContainer(
    overrides: [authProvider.overrideWith(() => notifier)],
  );
}

/// Runs [body] with defaultTargetPlatform overridden, always restoring it
/// afterwards via try/finally. addTearDown/tearDown fire AFTER Flutter's
/// _verifyInvariants check, which asserts no foundation debug var (including
/// debugDefaultTargetPlatformOverride) was left set — so the reset must
/// happen inside the test body itself.
Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('SocialLoginButtons platform gating', () {
    // Note: kIsWeb is a compile-time constant baked in at build time, so the
    // `!kIsWeb` branch of _supported can't be flipped from a non-web test
    // run via debugDefaultTargetPlatformOverride. We instead assert the
    // targetPlatform half of the gate (iOS/android show buttons; every
    // desktop TargetPlatform renders nothing), which is the part that is
    // actually exercisable here.
    testWidgets('renders nothing on linux desktop', (tester) async {
      await _withPlatform(TargetPlatform.linux, () async {
        final container = _containerFor(FakeAuthNotifier());
        addTearDown(container.dispose);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(find.byType(SocialLoginButtons), findsOneWidget);
        expect(find.text('or continue with'), findsNothing);
        expect(find.text('Continue with Google'), findsNothing);
      });
    });

    testWidgets('renders nothing on macos desktop', (tester) async {
      await _withPlatform(TargetPlatform.macOS, () async {
        final container = _containerFor(FakeAuthNotifier());
        addTearDown(container.dispose);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(find.text('or continue with'), findsNothing);
      });
    });

    testWidgets('renders nothing on windows desktop', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final container = _containerFor(FakeAuthNotifier());
        addTearDown(container.dispose);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(find.text('or continue with'), findsNothing);
      });
    });

    testWidgets('shows Google and Facebook but not Apple on Android',
        (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final container = _containerFor(FakeAuthNotifier());
        addTearDown(container.dispose);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.text('Continue with Facebook'), findsOneWidget);
        expect(find.text('Continue with Apple'), findsNothing);
      });
    });

    testWidgets('shows Google, Apple, and Facebook on iOS', (tester) async {
      await _withPlatform(TargetPlatform.iOS, () async {
        final container = _containerFor(FakeAuthNotifier());
        addTearDown(container.dispose);
        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.text('Continue with Apple'), findsOneWidget);
        expect(find.text('Continue with Facebook'), findsOneWidget);
      });
    });
  });

  group('SocialLoginButtons interaction', () {
    testWidgets('tapping a provider calls socialLogin with that provider',
        (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final fake = FakeAuthNotifier();
        final container = _containerFor(fake);
        addTearDown(container.dispose);
        await container.read(authProvider.future); // settle initial build()

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        await tester.tap(find.text('Continue with Google'));
        await tester.pump();
        await tester.pump(); // settle async

        expect(fake.socialLoginCalled, isTrue);
        expect(fake.lastProvider, SocialProvider.google);
      });
    });

    testWidgets('shows error text after a failed attempt', (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final fake = FakeAuthNotifier()
          ..errorToReturn = 'Google sign-in failed. Please try again.';
        final container = _containerFor(fake);
        addTearDown(container.dispose);
        await container.read(authProvider.future); // settle initial build()

        await tester.pumpWidget(_wrap(container));
        await tester.pump();

        await tester.tap(find.text('Continue with Google'));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Google sign-in failed. Please try again.'),
          findsOneWidget,
        );
      });
    });
  });
}
