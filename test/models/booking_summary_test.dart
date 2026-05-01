import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_summary.dart';

void main() {
  group('BookingSummary.fromJson', () {
    test('parses nested band field for non-personal band', () {
      final booking = BookingSummary.fromJson({
        'id': 1,
        'name': 'Wedding',
        'date': '2026-06-01',
        'is_paid': false,
        'contacts': [],
        'band': {
          'id': 10,
          'name': 'Test Band',
          'is_owner': true,
          'is_personal': false,
          'logo_url': 'https://example.com/logo.png',
        },
      });
      expect(booking.band, isNotNull);
      expect(booking.band!.id, equals(10));
      expect(booking.band!.name, equals('Test Band'));
      expect(booking.band!.isPersonal, isFalse);
      expect(booking.band!.logoUrl, equals('https://example.com/logo.png'));
    });

    test('parses nested band field for personal band', () {
      final booking = BookingSummary.fromJson({
        'id': 2,
        'name': 'Church',
        'date': '2026-06-02',
        'is_paid': false,
        'contacts': [],
        'band': {
          'id': 99,
          'name': "Eddie's Band",
          'is_owner': true,
          'is_personal': true,
          'logo_url': null,
        },
      });
      expect(booking.band, isNotNull);
      expect(booking.band!.isPersonal, isTrue);
      expect(booking.band!.logoUrl, isNull);
    });

    test('tolerates missing band field (legacy payloads)', () {
      final booking = BookingSummary.fromJson({
        'id': 3,
        'name': 'Old',
        'date': '2026-06-03',
        'is_paid': false,
        'contacts': [],
      });
      expect(booking.band, isNull);
    });

    test('tolerates explicit null band field', () {
      final booking = BookingSummary.fromJson({
        'id': 4,
        'name': 'Defensive',
        'date': '2026-06-04',
        'is_paid': false,
        'contacts': [],
        'band': null,
      });
      expect(booking.band, isNull);
    });
  });

  group('BookingSummary.displayPrice', () {
    test('formats null price as \$0.00', () {
      final booking = BookingSummary.fromJson({
        'id': 1,
        'name': 'Free Gig',
        'date': '2026-06-01',
        'is_paid': false,
        'contacts': [],
        // no 'price' key
      });
      expect(booking.displayPrice, equals(r'$0.00'));
    });

    test('formats numeric string price', () {
      final booking = BookingSummary.fromJson({
        'id': 2,
        'name': 'Paid',
        'date': '2026-06-01',
        'is_paid': false,
        'contacts': [],
        'price': '3500.00',
      });
      // Output is locale-dependent; just verify $ + digits + decimals show up.
      expect(booking.displayPrice, contains('3,500'));
      expect(booking.displayPrice, startsWith(r'$'));
    });

    test('returns raw price when not parseable', () {
      final booking = BookingSummary.fromJson({
        'id': 3,
        'name': 'Weird',
        'date': '2026-06-01',
        'is_paid': false,
        'contacts': [],
        'price': 'free',
      });
      expect(booking.displayPrice, equals('free'));
    });
  });
}
