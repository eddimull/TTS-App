import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';
import 'package:tts_bandmate/features/auth/providers/auth_provider.dart';
import 'package:tts_bandmate/features/auth/screens/login_screen.dart';

// ── Fake AuthNotifier ─────────────────────────────────────────────────────────

/// A notifier that records calls without touching the network.
class FakeAuthNotifier extends AuthNotifier {
  bool loginCalled = false;
  String? lastEmail;
  String? lastPassword;

  /// If true, login() will put an error message into state.
  bool shouldFail = false;

  @override
  Future<AuthState> build() async => const AuthUnauthenticated();

  @override
  Future<void> login(String email, String password) async {
    loginCalled = true;
    lastEmail = email;
    lastPassword = password;

    if (shouldFail) {
      state = const AsyncValue.data(
        AuthUnauthenticated(errorMessage: 'Invalid email or password.'),
      );
    } else {
      // Success — router would normally redirect; here we just set
      // authenticated state so the widget's post-login check passes.
      state = const AsyncValue.data(
        AuthAuthenticated(
          user: _fakeUser,
          bands: [],
        ),
      );
    }
  }
}

const _fakeUser = AuthUser(id: 1, name: 'Eddie', email: 'eddie@example.com');

// ── Widget wrapper ────────────────────────────────────────────────────────────

Widget _wrapWithProviders(
  Widget child, {
  FakeAuthNotifier? notifier,
}) {
  final fake = notifier ?? FakeAuthNotifier();
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => fake),
    ],
    child: CupertinoApp(
      theme: const CupertinoThemeData(
        primaryColor: CupertinoColors.systemBlue,
      ),
      home: child,
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('LoginScreen', () {
    testWidgets('test_renders_email_and_password_fields', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen()));
      await tester.pump();

      expect(find.widgetWithText(CupertinoTextField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(CupertinoTextField, 'Password'), findsOneWidget);
    });

    testWidgets('test_renders_sign_in_button', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen()));
      await tester.pump();

      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('test_shows_validation_error_when_email_empty', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen()));
      await tester.pump();

      // Tap Sign In without entering anything
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Please enter your email.'), findsOneWidget);
    });

    testWidgets('test_shows_validation_error_for_invalid_email', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen()));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Email'),
        'not-an-email',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('test_shows_validation_error_when_password_empty', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen()));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Email'),
        'valid@email.com',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Please enter your password.'), findsOneWidget);
    });

    testWidgets('test_calls_login_with_trimmed_credentials', (tester) async {
      final fake = FakeAuthNotifier();
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen(), notifier: fake));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Email'),
        '  eddie@example.com  ',
      );
      await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Password'),
        'secret123',
      );

      await tester.tap(find.text('Sign In'));
      await tester.pump();
      await tester.pump(); // settle async

      expect(fake.loginCalled, isTrue);
      expect(fake.lastEmail, 'eddie@example.com'); // trimmed
      expect(fake.lastPassword, 'secret123');
    });

    testWidgets('test_password_is_obscured_by_default', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen()));
      await tester.pump();

      // Find the EditableText inside the password CupertinoTextField
      final passwordFields = tester.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      ).toList();
      // Password is the second CupertinoTextField
      expect(passwordFields.length, greaterThanOrEqualTo(2));
      expect(passwordFields[1].obscureText, isTrue);
    });

    testWidgets('test_password_visibility_toggle_reveals_text', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen()));
      await tester.pump();

      // Tap the visibility toggle icon (eye icon)
      await tester.tap(find.byIcon(CupertinoIcons.eye));
      await tester.pump();

      final passwordFields = tester.widgetList<CupertinoTextField>(
        find.byType(CupertinoTextField),
      ).toList();
      expect(passwordFields[1].obscureText, isFalse);
    });

    testWidgets('test_shows_error_dialog_on_failed_login', (tester) async {
      final fake = FakeAuthNotifier()..shouldFail = true;
      await tester.pumpWidget(_wrapWithProviders(const LoginScreen(), notifier: fake));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Email'),
        'bad@example.com',
      );
      await tester.enterText(
        find.widgetWithText(CupertinoTextField, 'Password'),
        'wrongpass',
      );

      await tester.tap(find.text('Sign In'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Invalid email or password.'), findsOneWidget);
    });
  });
}
