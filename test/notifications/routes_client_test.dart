import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/notifications/data/routes_client.dart';

void main() {
  group('parseRoutesDuration', () {
    test('parses seconds string like "2705s"', () {
      final d = parseRoutesDuration({
        'routes': [
          {'duration': '2705s'}
        ]
      });
      expect(d, const Duration(seconds: 2705));
    });

    test('parses integer seconds', () {
      final d = parseRoutesDuration({
        'routes': [
          {'duration': 600}
        ]
      });
      expect(d, const Duration(seconds: 600));
    });

    test('null when no routes', () {
      expect(parseRoutesDuration({'routes': <dynamic>[]}), isNull);
      expect(parseRoutesDuration({}), isNull);
    });

    test('null when duration missing/garbage', () {
      expect(parseRoutesDuration({'routes': [{}]}), isNull);
      expect(parseRoutesDuration({'routes': [{'duration': 'abc'}]}), isNull);
    });
  });
}
