// Host-side flutter_driver test that drives the booking contract flow
// against a real Laravel backend.
//
// Run with:
//   chromedriver --port=4444 &
//   flutter drive \
//     --target=test_driver/contract_smoke.dart \
//     --driver=test_driver/contract_smoke_test.dart \
//     -d web-server \
//     --browser-name=chrome \
//     --headless \
//     --web-port=8765 \
//     --dart-define=BASE_URL=http://localhost:8080 \
//     --dart-define=SMOKE_EMAIL=eddimull+testuser@gmail.com \
//     --dart-define=SMOKE_PASSWORD=password \
//     --dart-define=SMOKE_DRAFT_BAND_ID=2 \
//     --dart-define=SMOKE_DRAFT_BOOKING_ID=639 \
//     --dart-define=SMOKE_LOCKED_BOOKING_ID=487

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

const String _email = String.fromEnvironment(
  'SMOKE_EMAIL',
  defaultValue: 'eddimull+testuser@gmail.com',
);
const String _password = String.fromEnvironment(
  'SMOKE_PASSWORD',
  defaultValue: 'password',
);
// ignore: unused_element
const String _bandId = String.fromEnvironment(
  'SMOKE_DRAFT_BAND_ID',
  defaultValue: '2',
);
// ignore: unused_element
const String _draftBookingId = String.fromEnvironment(
  'SMOKE_DRAFT_BOOKING_ID',
  defaultValue: '639',
);
// ignore: unused_element
const String _lockedBookingId = String.fromEnvironment(
  'SMOKE_LOCKED_BOOKING_ID',
  defaultValue: '487',
);

Future<void> _login(FlutterDriver driver) async {
  await driver.waitFor(find.text('Sign In'),
      timeout: const Duration(seconds: 30));
  // CupertinoTextField doesn't expose a stable selector; tap by position via
  // value-key would be cleaner but requires adding Keys to production code.
  // Instead we tap into the email field via its placeholder text, since
  // CupertinoTextField placeholders are visible to the a11y tree.
  // If placeholders don't match, fall back to tapping the first/second text
  // field by widget type.
  // For now, use the known placeholder strings from login_screen.dart.
  // (If the login screen's text fields have different placeholders, this
  //  needs adapting.)
  try {
    await driver.tap(find.byValueKey('login_email_field'),
        timeout: const Duration(seconds: 3));
    await driver.enterText(_email);
  } catch (_) {
    // No key — fall back: focus by tapping into the visible CupertinoTextField
    // via its placeholder text (assumes "Email" placeholder).
    await driver.tap(find.byTooltip('Email'),
        timeout: const Duration(seconds: 3));
    await driver.enterText(_email);
  }

  try {
    await driver.tap(find.byValueKey('login_password_field'),
        timeout: const Duration(seconds: 3));
    await driver.enterText(_password);
  } catch (_) {
    await driver.tap(find.byTooltip('Password'),
        timeout: const Duration(seconds: 3));
    await driver.enterText(_password);
  }

  await driver.tap(find.text('Sign In'));

  // Auth + (optional) band selection. Wait up to 20s for the login screen
  // to disappear.
  final loginGone = await _waitGone(
    driver,
    find.text('Sign In'),
    timeout: const Duration(seconds: 20),
  );
  expect(loginGone, isTrue, reason: 'should be past /login after auth');

  // If a band selector appears, tap "Test Band".
  try {
    await driver.waitFor(find.text('Test Band'),
        timeout: const Duration(seconds: 4));
    await driver.tap(find.text('Test Band'));
  } catch (_) {
    // Either auto-selected single band, or already past the selector.
  }
}

Future<bool> _waitGone(
  FlutterDriver driver,
  SerializableFinder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      await driver.waitForAbsent(finder,
          timeout: const Duration(seconds: 1));
      return true;
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }
  return false;
}

void main() {
  late FlutterDriver driver;

  setUpAll(() async {
    driver = await FlutterDriver.connect();
  });

  tearDownAll(() async {
    await driver.close();
  });

  test(
    'draft booking: editor renders, send sheet opens',
    () async {
      await _login(driver);

      // Deep-link the URL by pumping it through the JavaScript bridge.
      // flutter_driver doesn't expose direct router control; on web we can
      // simply change window.location.hash via requestData (custom handler
      // not registered) — fall back to hand-navigation by visiting the bookings
      // list. Easiest: rely on go_router URL strategy and just await a known
      // element after navigation.
      //
      // The dashboard / bookings flow is out of scope for this smoke; we
      // assert the editor surface by deep-linking via the URL hash. The
      // BandmateApp uses go_router which listens to URL changes.
      //
      // Note: flutter_driver lacks a built-in "go to URL" — this test relies
      // on the test_driver/contract_smoke.dart entrypoint preserving go_router
      // URL strategy. After login, the URL hash is empty, so we set it
      // explicitly via the WebDriver session ... but flutter_driver hides the
      // raw Selenium driver. Compromise: navigate via UI (find the booking
      // in the bookings list).

      // For this smoke we accept manual nav: open Bookings tab.
      try {
        await driver.tap(find.text('Bookings'),
            timeout: const Duration(seconds: 5));
      } catch (_) {
        // Already on bookings or no tab named "Bookings".
      }

      // Find the draft booking by name and tap it.
      await driver.waitFor(find.text('Test Booking'),
          timeout: const Duration(seconds: 10));
      await driver.tap(find.text('Test Booking'));

      // Find "Contract" tab/button on the booking detail screen and tap.
      await driver.waitFor(find.text('Contract'),
          timeout: const Duration(seconds: 8));
      await driver.tap(find.text('Contract'));

      // We should now see the editor — assert Send button + Preview/Edit pills.
      await driver.waitFor(find.text('Send'),
          timeout: const Duration(seconds: 8));
      await driver.waitFor(find.text('Preview'),
          timeout: const Duration(seconds: 3));

      // Open send sheet.
      await driver.tap(find.text('Send'));
      await driver.waitFor(find.text('Send Contract'),
          timeout: const Duration(seconds: 5));
      await driver.waitFor(find.text('Cancel'),
          timeout: const Duration(seconds: 2));

      // Cancel — do not send a real contract.
      await driver.tap(find.text('Cancel'));
      // Sheet dismissed → we're back on the editor.
      await driver.waitFor(find.text('Contract'),
          timeout: const Duration(seconds: 5));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
