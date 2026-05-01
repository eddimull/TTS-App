import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';

/// Minimal JSON that satisfies BookingDetail.fromJson's required fields.
Map<String, dynamic> _base({Map<String, dynamic>? bandOverride, bool omitBand = false}) {
  return {
    'id': 1,
    'name': 'Corporate Event',
    'date': '2026-07-15',
    'is_paid': false,
    'contacts': [],
    'events': [],
    'payments': [],
    if (!omitBand) 'band': bandOverride,
  };
}

void main() {
  group('BookingDetail.fromJson — band field', () {
    test('parses nested band field for a regular band', () {
      final detail = BookingDetail.fromJson(_base(bandOverride: {
        'id': 10,
        'name': 'The Riffmasters',
        'is_owner': true,
        'is_personal': false,
        'logo_url': 'https://cdn.example.com/logo.png',
      }));

      expect(detail.band, isNotNull);
      expect(detail.band!.id, equals(10));
      expect(detail.band!.name, equals('The Riffmasters'));
      expect(detail.band!.isPersonal, isFalse);
      expect(detail.band!.logoUrl, equals('https://cdn.example.com/logo.png'));
    });

    test('parses nested band field as personal band', () {
      final detail = BookingDetail.fromJson(_base(bandOverride: {
        'id': 99,
        'name': "Eddie's Personal",
        'is_owner': true,
        'is_personal': true,
        'logo_url': null,
      }));

      expect(detail.band, isNotNull);
      expect(detail.band!.isPersonal, isTrue);
      expect(detail.band!.logoUrl, isNull);
    });

    test('tolerates missing band key (legacy cached payloads)', () {
      final detail = BookingDetail.fromJson(_base(omitBand: true));
      expect(detail.band, isNull);
    });

    test('tolerates explicit null band value', () {
      final detail = BookingDetail.fromJson(_base(bandOverride: null));
      expect(detail.band, isNull);
    });
  });
}
