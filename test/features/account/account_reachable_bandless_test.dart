// Regression test for the Apple App Review requirement: a brand-new account
// with NO bands must still be able to reach the Account screen (and therefore
// the account-deletion flow). A band-less authenticated user is parked on the
// PathSelectionScreen ("Get Started"); the "Account" entry point there must
// navigate to /account, which the router must NOT redirect back to /bands.

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';

import '../../helpers/test_harness.dart';

void main() {
  setUp(stubConnectivityChannel);

  testWidgets('band-less user can reach the Account screen and delete flow',
      (tester) async {
    const user = {
      'id': 1,
      'name': 'Eddie',
      'email': 'eddie@example.com',
    };

    final harness = await bootstrapApp(
      initialLocation: '/dashboard',
      handler: (options) async {
        final path = options.path;

        // Authenticated, but with zero bands.
        if (path.endsWith(ApiEndpoints.mobileMe)) {
          return json(200, {
            'user': user,
            'bands': <Map<String, dynamic>>[],
          });
        }

        // Account profile + empty lookup lists.
        if (path.endsWith(ApiEndpoints.mobileAccount)) {
          return json(200, {
            'account': {
              'id': 1,
              'name': 'Eddie',
              'email': 'eddie@example.com',
              'email_notifications': true,
            },
            'states': <Map<String, dynamic>>[],
            'countries': <Map<String, dynamic>>[],
          });
        }

        return json(200, {'data': []});
      },
    );

    // Seed a token so the app boots authenticated.
    await harness.storage.writeToken('tok');

    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    // A band-less user is parked on the Get Started / path-selection screen.
    expect(find.text('How would you like to use Bandmate?'), findsOneWidget);

    // Tap the Account entry point in the nav bar.
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    // We're on the Account screen — the router did NOT bounce us to /bands.
    expect(find.widgetWithText(CupertinoNavigationBar, 'Account'),
        findsOneWidget);

    // The destructive delete action lives at the bottom of the scrollable
    // form — scroll it into view, then confirm it's reachable.
    final deleteButton = find.text('Delete Account');
    await tester.scrollUntilVisible(
      deleteButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(deleteButton, findsOneWidget);

    // Tapping it shows the confirmation dialog (deletion is initiable).
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
  });
}
