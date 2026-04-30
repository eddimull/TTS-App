// Widget-level "integration" test for the login → band-selection → dashboard
// flow.
//
// Uses the shared harness in test/helpers/test_harness.dart. Real router,
// real providers, real screens — only the HTTP layer and a couple of plugin
// channels are stubbed.
//
// Run with:
//   flutter test test/login_flow_widget_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';

import 'helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(stubConnectivityChannel);

  testWidgets(
    'login → single band auto-selects → leaves login screen',
    (tester) async {
      final harness = await bootstrapApp(
        handler: (options) async {
          final path = options.path;
          if (path.endsWith(ApiEndpoints.mobileToken)) {
            return json(200, {
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
            return json(200, {
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
          return json(200, {'data': []});
        },
      );

      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
      await snap(tester, '01_login_empty');

      await tester.enterText(
          find.byType(CupertinoTextField).at(0), 'eddie@example.com');
      await tester.enterText(
          find.byType(CupertinoTextField).at(1), 'password123');
      await tester.pump();
      await snap(tester, '02_login_filled');

      await tester.tap(find.text('Sign In'));
      // Bounded pump — destination dashboard screen has streams that don't
      // settle, so pumpAndSettle would hang.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await harness.storage.readToken(), 'fake-token-xyz');
      expect(find.text('Sign In'), findsNothing);

      await snap(tester, '03_after_signin');
    },
  );
}
