import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/library/data/models/chart.dart';

void main() {
  group('Chart.fromJson — band block', () {
    test('parses nested band object with all fields', () {
      final chart = Chart.fromJson({
        'id': 1,
        'band_id': 7,
        'title': 'Stardust',
        'composer': 'Hoagy Carmichael',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        'band': {
          'id': 7,
          'name': 'Trio',
          'is_personal': false,
          'logo_url': 'https://example.com/logo.png',
        },
      });

      expect(chart.band, isNotNull);
      expect(chart.band!.id, 7);
      expect(chart.band!.name, 'Trio');
      expect(chart.band!.isPersonal, false);
      expect(chart.band!.logoUrl, 'https://example.com/logo.png');
    });

    test('parses is_personal: true for personal band', () {
      final chart = Chart.fromJson({
        'id': 2,
        'band_id': 9,
        'title': 'Etude',
        'composer': '',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        'band': {
          'id': 9,
          'name': "Eddie's Band",
          'is_personal': true,
          'logo_url': null,
        },
      });

      expect(chart.band!.isPersonal, true);
      expect(chart.band!.logoUrl, isNull);
    });

    test('tolerates missing band field (per-band endpoint response)', () {
      final chart = Chart.fromJson({
        'id': 3,
        'band_id': 5,
        'title': 'Body and Soul',
        'composer': '',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        // no 'band' key
      });

      expect(chart.band, isNull);
      expect(chart.title, 'Body and Soul');
    });

    test('tolerates band: null', () {
      final chart = Chart.fromJson({
        'id': 4,
        'band_id': 5,
        'title': 'Caravan',
        'composer': '',
        'description': '',
        'price': 0,
        'public': false,
        'uploads_count': 0,
        'band': null,
      });

      expect(chart.band, isNull);
    });
  });
}
