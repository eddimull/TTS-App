import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/auth/data/models/band_summary.dart';

void main() {
  group('BandSummary.fromJson', () {
    test('parses isPersonal=true', () {
      final band = BandSummary.fromJson({
        'id': 1,
        'name': 'Personal',
        'is_owner': true,
        'is_personal': true,
        'logo_url': null,
      });
      expect(band.isPersonal, isTrue);
      expect(band.logoUrl, isNull);
    });

    test('parses isPersonal=false', () {
      final band = BandSummary.fromJson({
        'id': 2,
        'name': 'Real Band',
        'is_owner': false,
        'is_personal': false,
        'logo_url': 'https://example.com/logo.png',
      });
      expect(band.isPersonal, isFalse);
      expect(band.logoUrl, equals('https://example.com/logo.png'));
    });

    test('defaults isPersonal to false when missing (legacy payloads)', () {
      final band = BandSummary.fromJson({
        'id': 3,
        'name': 'Legacy',
        'is_owner': false,
      });
      expect(band.isPersonal, isFalse);
      expect(band.logoUrl, isNull);
    });
  });
}
