import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/data/models/booking_detail.dart';
import 'package:tts_bandmate/features/bookings/data/models/deposit.dart';

void main() {
  group('Deposit.resolve', () {
    test('prefers backend expectedDepositAmount when present', () {
      final resolved = Deposit.resolve(_booking(
        price: '1000.00',
        depositType: 'percent',
        depositValue: '50.00',
        expectedDepositAmount: '500.00',
      ));
      expect(resolved.depositAmount, '500.00');
      expect(resolved.remainingAmount, '500.00');
    });

    test('computes percent client-side when expectedDepositAmount absent', () {
      final resolved = Deposit.resolve(_booking(
        price: '1000.00',
        depositType: 'percent',
        depositValue: '25.00',
        expectedDepositAmount: null,
      ));
      expect(resolved.depositAmount, '250.00');
      expect(resolved.remainingAmount, '750.00');
    });

    test('computes amount client-side when expectedDepositAmount absent', () {
      final resolved = Deposit.resolve(_booking(
        price: '1000.00',
        depositType: 'amount',
        depositValue: '300.00',
        expectedDepositAmount: null,
      ));
      expect(resolved.depositAmount, '300.00');
      expect(resolved.remainingAmount, '700.00');
    });

    test('returns 0.00 when price is null or zero', () {
      final resolved = Deposit.resolve(_booking(
        price: null,
        depositType: 'percent',
        depositValue: '50.00',
      ));
      expect(resolved.depositAmount, '0.00');
      expect(resolved.remainingAmount, '0.00');
    });
  });
}

BookingDetail _booking({
  String? price,
  String depositType = 'percent',
  String depositValue = '50.00',
  String? expectedDepositAmount,
}) =>
    BookingDetail.fromJson({
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
      'price': price,
      'deposit_type': depositType,
      'deposit_value': depositValue,
      if (expectedDepositAmount != null)
        'expected_deposit_amount': expectedDepositAmount,
    });
