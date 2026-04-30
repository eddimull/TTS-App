// Widget-level E2E tests for the post-signup onboarding branches: solo,
// create-band (skip / with invites), and join-via-QR.
//
// Each test starts with no token and ends on /dashboard, with a screenshot
// of the final state under test/screenshots/.
//
// Run with:
//   flutter test test/onboarding_flows_widget_test.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tts_bandmate/core/network/api_endpoints.dart';

import 'helpers/test_harness.dart';

// Constants & helpers for stubbing mobile_scanner platform channels. The
// package uses an EventChannel for barcode events; we register a mock stream
// handler so we can synthesize a barcode detection event from the test.

const _scannerMethodChannelName =
    'dev.steenbakker.mobile_scanner/scanner/method';
const _scannerEventChannelName =
    'dev.steenbakker.mobile_scanner/scanner/event';

/// Stub the mobile_scanner method channel: respond to permission, start, and
/// teardown methods so the [MobileScanner] widget can mount.
void _stubScannerMethodChannel() {
  const methodChannel = MethodChannel(_scannerMethodChannelName);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(methodChannel, (call) async {
    switch (call.method) {
      case 'state':
        return 1; // authorized
      case 'request':
        return true;
      case 'start':
        return {
          'textureId': 0,
          'numberOfCameras': 1,
          'currentTorchState': -1,
          'size': {'width': 1080.0, 'height': 1920.0},
        };
      case 'stop':
      case 'pause':
      case 'toggleTorch':
      case 'setScale':
      case 'resetScale':
      case 'updateScanWindow':
      case 'setInvertImage':
        return null;
      default:
        return null;
    }
  });

  // EventChannel.receiveBroadcastStream() sends 'listen' and 'cancel' through
  // a MethodChannel with the same name as the EventChannel. Stub those so the
  // subscription doesn't throw a MissingPluginException.
  const eventMethodChannel = MethodChannel(_scannerEventChannelName);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(eventMethodChannel, (call) async => null);
}

/// Send a barcode-detected event through the mobile_scanner event channel.
/// Call after the [MobileScanner] widget has mounted and subscribed.
Future<void> _emitScannerBarcode(WidgetTester tester, String code) async {
  final encoded =
      const StandardMethodCodec().encodeSuccessEnvelope({
    'name': 'barcode',
    'data': [
      {
        'rawValue': code,
        'format': -1, // BarcodeFormat.unknown – the screen ignores format
        'corners': <Map<String, double>>[],
      },
    ],
  });

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _scannerEventChannelName,
    encoded,
    (_) {},
  );
  await tester.pump();
}

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

    testWidgets('signup → join via QR → dashboard', (tester) async {
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

      // mobile_scanner only parses barcode events on Android/iOS/macOS.
      // Override the platform for the duration of this test so the parser
      // doesn't throw on Linux.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      _stubScannerMethodChannel();

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

      await signUpAs(tester);

      // /bands → "Join a Band" → /bands/join
      await tester.tap(find.text('Join a Band'));
      await tester.pumpAndSettle();

      // /bands/join → tap "Scan QR Code" → scanner mounts.
      await tester.tap(find.text('Scan QR Code'));
      // Pump enough frames for the MobileScanner widget to subscribe to its
      // event channel. We don't pumpAndSettle because the scanner has
      // continuous frames that never quiesce.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Synthesize a barcode detection — the screen's onDetect calls
      // _joinWithKey with the rawValue.
      await _emitScannerBarcode(tester, 'ABC123');

      // Pump for the join request → refreshBands → /me → router redirect.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final joinBodies =
          harness.capturedBodies[ApiEndpoints.mobileBandsJoin];
      expect(joinBodies, isNotNull,
          reason: 'Expected at least one POST to mobileBandsJoin');
      expect(joinBodies!.first, {'key': 'ABC123'});

      expect(await harness.storage.readToken(), 'tok');
      expect(find.text('Sign In'), findsNothing);
      expect(find.text('Scan QR Code'), findsNothing);

      await snap(tester, 'join_qr_01_dashboard');

      // Reset the platform override before _verifyInvariants runs.
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
