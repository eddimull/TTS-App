import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

// Source-level guards: these assert the route wiring facts that widget tests
// can't reach cheaply (redirect + list membership), so a refactor can't
// silently drop them.
void main() {
  final router = File('lib/core/config/router.dart').readAsStringSync();
  final mainDart = File('lib/main.dart').readAsStringSync();

  test('shell prefixes swapped: settings/messages/operations in, more out', () {
    final block = router.split('_kShellPrefixes')[1].split('];').first;
    expect(block, contains("'/settings'"));
    expect(block, contains("'/messages'"));
    expect(block, contains("'/operations'"));
    expect(block, contains("'/bookings'"));
    expect(block, isNot(contains("'/more'")));
  });

  test('restorable prefixes match', () {
    final block = mainDart.split('_kRestorableShellPrefixes')[1].split('];').first;
    expect(block, contains("'/settings'"));
    expect(block, contains("'/messages'"));
    expect(block, contains("'/bookings'"));
    expect(block, isNot(contains("'/more'")));
  });

  test('/more redirects to /settings and MoreScreen is gone', () {
    expect(router, contains("path: '/more'"));
    expect(router, contains("redirect: (_, __) => '/settings'"));
    expect(router, isNot(contains('MoreScreen')));
    expect(File('lib/features/more/screens/more_screen.dart').existsSync(), isFalse);
  });
}
