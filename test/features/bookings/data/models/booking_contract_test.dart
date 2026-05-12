import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';

void main() {
  group('BookingContract', () {
    test('fromJson parses custom_terms and updated_at', () {
      final c = BookingContract.fromJson({
        'id': 1,
        'status': 'draft',
        'asset_url': null,
        'envelope_id': null,
        'custom_terms': [
          {'title': 'A', 'content': 'B'}
        ],
        'updated_at': '2026-05-11T12:00:00Z',
      });
      expect(c.customTerms, isNotNull);
      expect(c.customTerms!.length, 1);
      expect(c.customTerms!.first.title, 'A');
      expect(c.updatedAt, isNotNull);
      expect(c.updatedAt!.year, 2026);
    });

    test('fromJson null custom_terms stays null', () {
      final c = BookingContract.fromJson({'id': 1});
      expect(c.customTerms, isNull);
      expect(c.updatedAt, isNull);
    });
  });
}
