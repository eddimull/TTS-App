import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/auth_user.dart';

void main() {
  group('AuthUser.fromJson', () {
    test('parses avatarUrl when present', () {
      final user = AuthUser.fromJson({
        'id': 1,
        'name': 'Eddie',
        'email': 'e@e.com',
        'avatar_url': 'https://example.com/me.png',
      });
      expect(user.avatarUrl, equals('https://example.com/me.png'));
    });

    test('parses null avatarUrl', () {
      final user = AuthUser.fromJson({
        'id': 2,
        'name': 'Sam',
        'email': 's@e.com',
        'avatar_url': null,
      });
      expect(user.avatarUrl, isNull);
    });

    test('defaults avatarUrl to null when key missing (legacy cached payload)', () {
      final user = AuthUser.fromJson({
        'id': 3,
        'name': 'Pat',
        'email': 'p@e.com',
      });
      expect(user.avatarUrl, isNull);
    });

    test('round-trips via toJson/fromJsonString', () {
      const original = AuthUser(
        id: 4,
        name: 'Roundtrip',
        email: 'r@r.com',
        avatarUrl: 'https://example.com/r.png',
      );
      final round = AuthUser.fromJsonString(original.toJsonString());
      expect(round.avatarUrl, equals('https://example.com/r.png'));
    });
  });
}
