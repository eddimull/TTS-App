import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/bookings/services/booking_save_orchestrator.dart';

void main() {
  group('BookingSaveResult predicates', () {
    test('allSucceeded — every op success', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationSuccess(),
        eventUpdates: {'evt_1': const OperationSuccess()},
        eventCreates: const {},
        eventDeletes: const {},
      );
      expect(r.allSucceeded, isTrue);
      expect(r.partiallySucceeded, isFalse);
      expect(r.allFailed, isFalse);
      expect(r.failedCount, 0);
    });

    test('allFailed — every ran op failed', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationFailure('boom'),
        eventUpdates: {'evt_1': const OperationFailure('boom')},
        eventCreates: const {},
        eventDeletes: const {},
      );
      expect(r.allSucceeded, isFalse);
      expect(r.partiallySucceeded, isFalse);
      expect(r.allFailed, isTrue);
      expect(r.failedCount, 2);
    });

    test('partiallySucceeded — mixed success and failure', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationSuccess(),
        eventUpdates: {
          'evt_1': const OperationSuccess(),
          'evt_2': const OperationFailure('nope'),
        },
        eventCreates: {
          'new-1': const OperationSuccess(),
        },
        eventDeletes: {
          7: const OperationFailure('cannot delete last event'),
        },
      );
      expect(r.partiallySucceeded, isTrue);
      expect(r.failedCount, 2);
    });

    test('failureKeys yields BOOKING / EVT- / NEW- prefixed keys', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationFailure('booking failed'),
        eventUpdates: {'evt_2': const OperationFailure('update failed')},
        eventCreates: {'new-1': const OperationFailure('create failed')},
        eventDeletes: {9: const OperationFailure('delete failed')},
      );
      final keys = r.failureKeys.map((e) => e.key).toList();
      expect(keys, containsAll(['BOOKING', 'EVT-evt_2', 'NEW-new-1', 'EVT-9']));
    });

    test('all-pending result is not allFailed', () {
      final r = BookingSaveResult(
        bookingPatch: const OperationPending(),
        eventUpdates: const {},
        eventCreates: const {},
        eventDeletes: const {},
      );
      expect(r.allFailed, isFalse,
          reason: 'allFailed requires at least one op to have run');
    });
  });
}
