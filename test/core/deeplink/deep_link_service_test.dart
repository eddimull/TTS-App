import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/deeplink/deep_link_service.dart';

void main() {
  group('inviteRouteForUri', () {
    test('maps an /invite/<key> URI to the invite route', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/invite/abc123')),
        '/invite/abc123',
      );
    });

    test('tolerates a trailing slash', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/invite/abc123/')),
        '/invite/abc123',
      );
    });

    test('returns null for a non-invite path', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/dashboard')),
        isNull,
      );
    });

    test('returns null for an invite URL missing the key', () {
      expect(
        inviteRouteForUri(Uri.parse('https://tts.band/invite/')),
        isNull,
      );
    });
  });
}
