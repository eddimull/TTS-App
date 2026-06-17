// Regression test for the Copilot round-3 finding: the account form must
// reflect a reloaded profile, not just the initial one. The parent reuses the
// _AccountForm State across provider rebuilds, so didUpdateWidget must re-sync
// the controllers when the profile changes.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';
import 'package:tts_bandmate/features/account/providers/account_provider.dart';

import '../../helpers/test_harness.dart';

void main() {
  setUp(stubConnectivityChannel);

  testWidgets('account form re-syncs fields after a profile reload',
      (tester) async {
    const user = {'id': 1, 'name': 'Eddie', 'email': 'eddie@example.com'};

    // Mutable name the /account stub returns; flip it to simulate a reload.
    var profileName = 'Old Name';

    final harness = await bootstrapApp(
      initialLocation: '/account',
      handler: (options) async {
        final path = options.path;
        if (path.endsWith(ApiEndpoints.mobileMe)) {
          return json(200, {
            'user': user,
            'bands': [
              {'id': 10, 'name': 'Eds', 'is_owner': true}
            ],
          });
        }
        if (path.endsWith(ApiEndpoints.mobileAccount)) {
          return json(200, {
            'account': {
              'id': 1,
              'name': profileName,
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

    await harness.storage.writeToken('tok');
    await harness.storage.writeBandId('10');

    await tester.pumpWidget(harness.widget);
    await tester.pumpAndSettle();

    // Initial profile is reflected in the form.
    expect(find.widgetWithText(CupertinoTextField, 'Old Name'), findsOneWidget);

    // Simulate the server returning updated data, then reload the provider.
    // The parent rebuilds _AccountForm with the new profile while Flutter
    // reuses its State — the exact didUpdateWidget scenario under test.
    //
    // reload() briefly flips the provider to AsyncValue.loading(), which shows
    // a CupertinoActivityIndicator (a perpetual animation). pumpAndSettle would
    // wait on it forever, so pump fixed frames instead.
    profileName = 'New Name';
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CupertinoTextField).first),
    );
    unawaited(container.read(accountProvider.notifier).reload());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The reused form State must now show the reloaded values.
    expect(find.widgetWithText(CupertinoTextField, 'New Name'), findsOneWidget);
    expect(find.widgetWithText(CupertinoTextField, 'Old Name'), findsNothing);
  });
}
