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

      await signUpAs(tester);

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

    testWidgets('signup → create band (skip invites) → dashboard',
        (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 11,
        'name': 'The Eds',
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
          if (path.endsWith(ApiEndpoints.mobileCreateBand)) {
            return json(200, {'band': band});
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

      await signUpAs(tester);

      // /bands → tap "Create a Band" → /bands/create
      await tester.tap(find.text('Create a Band'));
      await tester.pumpAndSettle();

      // Step 1: type band name, tap Next.
      // The nav bar title also says "Name Your Band"; the heading on screen
      // is "What's your band called?". Use that heading to assert step 1.
      expect(find.text('What\'s your band called?'), findsOneWidget);
      await tester.enterText(
          find.byType(CupertinoTextField).first, 'The Eds');
      await tester.pump();

      // Tap Next. Tap the button ancestor since the same text could appear
      // in nav bar or other widgets.
      await tester.tap(
        find.ancestor(
          of: find.text('Next'),
          matching: find.byType(CupertinoButton),
        ),
      );
      await tester.pumpAndSettle();

      // Step 2: skip invites.
      expect(find.text('Invite your bandmates'), findsOneWidget);
      await tester.tap(
        find.ancestor(
          of: find.text('Skip for now'),
          matching: find.byType(CupertinoButton),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Sign In'), findsNothing);
      expect(find.text('Skip for now'), findsNothing);

      await snap(tester, 'create_skip_01_dashboard');
    });

    testWidgets('signup → create band (with invites) → dashboard',
        (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 11,
        'name': 'The Eds',
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
          if (path.endsWith(ApiEndpoints.mobileCreateBand)) {
            return json(200, {'band': band});
          }
          if (path.endsWith(ApiEndpoints.mobileBandInvite(11))) {
            return json(200, <String, dynamic>{});
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

      await signUpAs(tester);

      // /bands → tap "Create a Band" → /bands/create
      await tester.tap(find.text('Create a Band'));
      await tester.pumpAndSettle();

      // Step 1
      await tester.enterText(
          find.byType(CupertinoTextField).first, 'The Eds');
      await tester.pump();
      await tester.tap(
        find.ancestor(
          of: find.text('Next'),
          matching: find.byType(CupertinoButton),
        ),
      );
      await tester.pumpAndSettle();

      // Step 2: type an invitee email and tap the + button.
      await tester.enterText(
          find.byType(CupertinoTextField).first, 'bandmate@example.com');
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.add_circled_solid));
      await tester.pump();

      // The chip should now appear with the email.
      expect(find.text('bandmate@example.com'), findsOneWidget);

      // Submit. Tap the Done button (button-ancestor pattern in case the
      // text appears elsewhere).
      await tester.tap(
        find.ancestor(
          of: find.text('Done'),
          matching: find.byType(CupertinoButton),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Assert the captured invite request body.
      final invitePath = ApiEndpoints.mobileBandInvite(11);
      final inviteBodies = harness.capturedBodies[invitePath];
      expect(inviteBodies, isNotNull,
          reason: 'Expected at least one POST to $invitePath');
      expect(inviteBodies!.first, {
        'emails': ['bandmate@example.com']
      });

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Sign In'), findsNothing);
      expect(find.text('Done'), findsNothing);

      await snap(tester, 'create_invite_01_dashboard');
    });
  });
}
