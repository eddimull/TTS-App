// Widget-level E2E tests for the invite QR deep-link flow:
//   https://tts.band/invite/<key>
// forwarded by DeepLinkService to the /invite/:key route
// (InviteLandingScreen), which either joins immediately (authed) or stashes
// the key for the router's post-login listener to consume (unauthed).
//
// Mirrors the patterns in test/onboarding_flows_widget_test.dart (fake
// responses, bounded pump loops, captured-body assertions) and
// test/login_flow_widget_test.dart (driving the login form).
//
// Run with:
//   flutter test test/invite_deeplink_flow_widget_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(stubConnectivityChannel);

  group('invite deep link', () {
    testWidgets('authed deep link joins immediately → dashboard',
        (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 12,
        'name': 'The Eds',
        'is_owner': false,
      };

      final harness = await bootstrapApp(
        initialLocation: '/invite/TESTKEY123',
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileBandsJoin)) {
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

      // Seed a token so the app boots already authenticated.
      await harness.storage.writeToken('tok');

      await tester.pumpWidget(harness.widget);
      // Bounded pump — landing screen joins → refreshBands → /me → router
      // redirect to /dashboard; dashboard has streams that don't settle.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final joinBodies = harness.capturedBodies[ApiEndpoints.mobileBandsJoin];
      expect(joinBodies, isNotNull,
          reason: 'Expected at least one POST to mobileBandsJoin');
      expect(joinBodies!.first, {'key': 'TESTKEY123'});

      expect(find.text('Sign In'), findsNothing);
      expect(find.text('Log In'), findsNothing);

      await snap(tester, 'invite_deeplink_authed_01_dashboard');
    });

    testWidgets(
        'unauthed deep link stashes key, then auto-joins after login',
        (tester) async {
      const user = {
        'id': 1,
        'name': 'Eddie',
        'email': 'eddie@example.com',
      };
      const band = {
        'id': 12,
        'name': 'The Eds',
        'is_owner': false,
      };

      final harness = await bootstrapApp(
        initialLocation: '/invite/TESTKEY123',
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileToken)) {
            return json(200, {
              'token': 'fake-token-xyz',
              'user': user,
              'bands': <Map<String, dynamic>>[],
            });
          }
          if (path.endsWith(ApiEndpoints.mobileBandsJoin)) {
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

      // Unauthenticated — the invite landing screen stashed the key and sent
      // us to /welcome. No join request should have fired yet.
      expect(harness.capturedBodies[ApiEndpoints.mobileBandsJoin], isNull,
          reason: 'Join must not fire before authentication');
      expect(find.text('Log In'), findsOneWidget);

      // Drive to the login form and sign in (mirrors login_flow_widget_test).
      await tester.tap(find.text('Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);

      await tester.enterText(
          find.byType(CupertinoTextField).at(0), 'eddie@example.com');
      await tester.enterText(
          find.byType(CupertinoTextField).at(1), 'password123');
      await tester.pump();

      await tester.tap(find.text('Sign In'));
      // Bounded pump — login → auth listener consumes the pending invite →
      // join → refreshBands → /me → router redirect to /dashboard.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await harness.storage.readToken(), 'fake-token-xyz');

      final joinBodies = harness.capturedBodies[ApiEndpoints.mobileBandsJoin];
      expect(joinBodies, isNotNull,
          reason: 'Expected the post-login listener to POST the pending '
              'invite key');
      expect(joinBodies!.first, {'key': 'TESTKEY123'});

      expect(find.text('Sign In'), findsNothing);

      await snap(tester, 'invite_deeplink_unauthed_01_dashboard');
    });
  });
}
