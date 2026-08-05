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

  group('BookingDetail.fromJson lodgings', () {
    test('lodgings defaults to empty when key missing', () {
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
      });

      expect(detail.lodgings, isEmpty);
    });

    test('parses lodgings summary list', () {
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
        'lodgings': [
          {
            'id': 7,
            'name': 'Tour Hotel',
            'check_in_at': '2030-06-01 15:00:00',
            'check_out_at': '2030-06-02 11:00:00',
            'room_count': 3,
            'attachment_count': 1,
            'booking_id': 1,
          }
        ],
      });

      expect(detail.lodgings, hasLength(1));
      expect(detail.lodgings.single.name, 'Tour Hotel');
      expect(detail.lodgings.single.roomCount, 3);
      expect(detail.lodgings.single.bookingId, 1);
    });
  });
}
