import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/config/app_config.dart';
import 'package:tts_bandmate/features/bands/data/invite_key.dart';

void main() {
  group('extractInviteKey', () {
    test('returns raw key unchanged', () {
      expect(extractInviteKey('abc123'), 'abc123');
    });

    test('trims surrounding whitespace on a raw key', () {
      expect(extractInviteKey('  abc123 '), 'abc123');
    });

    test('extracts key from a full https invite URL', () {
      expect(extractInviteKey('https://tts.band/invite/abc123'), 'abc123');
    });

    test('extracts key from a URL with a trailing slash', () {
      expect(extractInviteKey('https://tts.band/invite/abc123/'), 'abc123');
    });

    test('extracts key from a URL with query params', () {
      expect(
        extractInviteKey('https://tts.band/invite/abc123?ref=qr'),
        'abc123',
      );
    });

    test('extracts key regardless of host (www)', () {
      expect(extractInviteKey('https://www.tts.band/invite/abc123'), 'abc123');
    });

    test('returns null for empty input', () {
      expect(extractInviteKey('   '), isNull);
    });

    test('returns null for an invite URL with no key segment', () {
      expect(extractInviteKey('https://tts.band/invite/'), isNull);
    });

    test('returns a non-invite URL as-is (treated as a raw key)', () {
      // A pasted non-URL string that happens to contain no scheme is a raw key.
      expect(extractInviteKey('not-a-url-code'), 'not-a-url-code');
    });
  });

  group('buildInviteUrl', () {
    test('composes host + /invite/ + key', () {
      expect(
        buildInviteUrl('abc123'),
        '${AppConfig.inviteBaseUrl}/invite/abc123',
      );
    });
  });
}
