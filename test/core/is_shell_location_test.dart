import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/config/router.dart';

// Unit tests for isShellLocation — the exact-match helper that decides
// whether a notification deeplink must be reached with `go` (shell tabs)
// rather than `push` (everything else). See notifications_screen_test.dart
// for the end-to-end router-hosted coverage of the same branching.
void main() {
  test('dashboard is a shell location', () {
    expect(isShellLocation('/dashboard'), isTrue);
  });

  test('band-settings is a shell location', () {
    expect(isShellLocation('/band-settings'), isTrue);
  });

  test('a booking detail path is NOT a shell location', () {
    // /bookings IS a shell tab, but /bookings/1/695 is the distinct
    // top-level /bookings/:bandId/:id route (no tab bar) — a naive prefix
    // match would wrongly treat this as a shell location.
    expect(isShellLocation('/bookings/1/695'), isFalse);
  });

  test('a conversation thread path is NOT a shell location', () {
    expect(isShellLocation('/conversations/3'), isFalse);
  });
}
