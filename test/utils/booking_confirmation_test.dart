import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/shared/utils/booking_confirmation.dart';

void main() {
  group('bookingConfirmationFromStatus', () {
    test('returns confirmed for "confirmed"', () {
      expect(bookingConfirmationFromStatus('confirmed'),
          BookingConfirmation.confirmed);
    });

    test('returns confirmed for "Confirmed" (case-insensitive)', () {
      expect(bookingConfirmationFromStatus('Confirmed'),
          BookingConfirmation.confirmed);
    });

    test('returns confirmed for "booked"', () {
      expect(bookingConfirmationFromStatus('booked'),
          BookingConfirmation.confirmed);
    });

    test('returns confirmed for "accepted"', () {
      expect(bookingConfirmationFromStatus('accepted'),
          BookingConfirmation.confirmed);
    });

    test('returns cancelled for "cancelled"', () {
      expect(bookingConfirmationFromStatus('cancelled'),
          BookingConfirmation.cancelled);
    });

    test('returns cancelled for "canceled" (US spelling)', () {
      expect(bookingConfirmationFromStatus('canceled'),
          BookingConfirmation.cancelled);
    });

    test('returns cancelled for any string containing "cancel"', () {
      expect(bookingConfirmationFromStatus('Cancellation pending'),
          BookingConfirmation.cancelled);
    });

    test('returns pending for "pending"', () {
      expect(bookingConfirmationFromStatus('pending'),
          BookingConfirmation.pending);
    });

    test('returns pending for null', () {
      expect(bookingConfirmationFromStatus(null), BookingConfirmation.pending);
    });

    test('returns pending for unknown strings', () {
      expect(bookingConfirmationFromStatus('foobar'),
          BookingConfirmation.pending);
    });

    test('returns pending for empty string', () {
      expect(bookingConfirmationFromStatus(''), BookingConfirmation.pending);
    });
  });
}
