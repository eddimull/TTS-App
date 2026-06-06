import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_contract.dart';

void main() {
  group('BookingContract.fromJson', () {
    test('parses buyer_name_override when present', () {
      final c = BookingContract.fromJson({
        'id': 1,
        'buyer_name_override': 'The City of Scott',
        'custom_terms': <dynamic>[],
      });
      expect(c.buyerNameOverride, 'The City of Scott');
    });

    test('buyer_name_override is null when absent', () {
      final c = BookingContract.fromJson({'id': 1});
      expect(c.buyerNameOverride, isNull);
    });
  });
}
