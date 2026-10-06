import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// App code must read the time through package:clock (`clock.now()`) so tests
// can pin it with `withClock(Clock.fixed(...), ...)`. A raw DateTime.now()
// bypasses that and makes date-dependent tests start failing as the real
// calendar moves on.
void main() {
  test('lib/ uses clock.now instead of DateTime.now', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        // Also catches the `DateTime.now` tear-off form.
        if (RegExp(r'\bDateTime\.now\b').hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use clock.now() from package:clock instead of DateTime.now()');
  });
}
