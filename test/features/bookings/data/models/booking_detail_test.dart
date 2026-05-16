import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';

void main() {
  group('BookingDetail.fromJson deposit fields', () {
    test('parses depositType, depositValue, expectedDepositAmount', () {
      final detail = BookingDetail.fromJson({
        'id': 1,
        'name': 'Test',
        'start_date': '2026-06-01',
        'end_date': '2026-06-01',
        'event_count': 1,
        'is_multi_event': false,
        'is_paid': false,
        'contacts': [],
        'events': [],
        'payments': [],
        'price': '1000.00',
        'deposit_type': 'amount',
        'deposit_value': '250.00',
        'expected_deposit_amount': '250.00',
      });

      expect(detail.depositType, 'amount');
      expect(detail.depositValue, '250.00');
      expect(detail.expectedDepositAmount, '250.00');
    });

    test('falls back to "percent" / "50.00" when fields absent (legacy responses)', () {
      final detail = BookingDetail.fromJson({
        'id': 1,
        'name': 'Test',
        'start_date': '2026-06-01',
        'end_date': '2026-06-01',
        'event_count': 1,
        'is_multi_event': false,
        'is_paid': false,
        'contacts': [],
        'events': [],
        'payments': [],
        'price': '1000.00',
      });

      expect(detail.depositType, 'percent');
      expect(detail.depositValue, '50.00');
      expect(detail.expectedDepositAmount, null);
    });
  });
}
