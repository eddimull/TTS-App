// Widget-level E2E tests for the post-signup onboarding branches: solo,
// create-band (skip / with invites), and join-via-QR.
//
// Each test starts with no token and ends on /dashboard, with a screenshot
// of the final state under test/screenshots/.
//
// Run with:
//   flutter test test/onboarding_flows_widget_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(stubConnectivityChannel);

  group('onboarding flows', () {
    testWidgets('signup → go solo → dashboard', (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 10,
        'name': 'Eddie',
        'is_owner': true,
      };

      final harness = await bootstrapApp(
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileRegister)) {
            return json(200, {
              'token': 'tok',
              'user': user,
              'bands': <Map<String, dynamic>>[],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileBandsSolo)) {
            return json(200, {
              'bands': [band],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileMe)) {
            return json(200, {
              'user': user,
              'bands': [band],
            });
          }
          return json(200, {'data': []});
        },
      );

      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      // /login → tap "Sign up" → /signup
      await tester.tap(find.text('Sign up'));
      await tester.pumpAndSettle();

      // Fill signup: name, email, password, confirm.
      // Use placeholder text to find fields unambiguously; login screen's
      // fields are still in the tree beneath the pushed signup screen.
      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Full Name'), 'Eddie Mullins');
      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Email').last,
          'eddie@example.com');
      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Password').last,
          'password123');
      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Confirm Password'),
          'password123');
      await tester.pump();

      // Submit. After register completes, router redirects to /bands
      // because bands list is empty.
      // The nav bar also shows "Create Account" as its title; tap the ancestor
      // CupertinoButton (not the raw Text node) so the onPressed fires.
      await tester.tap(
        find.ancestor(
          of: find.text('Create Account'),
          matching: find.byType(CupertinoButton),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Path-selection screen heading.
      expect(find.text('How would you like to use Bandmate?'), findsOneWidget);

      // Tap Go Solo card. After /bands/solo and /me complete, single-band
      // auto-select kicks in and router lands on /dashboard.
      await tester.tap(find.text('Go Solo'));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Sign In'), findsNothing);
      expect(
          find.text('How would you like to use Bandmate?'), findsNothing);

      await snap(tester, 'solo_01_dashboard');
    });
  });
}
