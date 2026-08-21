import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/core/network/reachability.dart';

void main() {
  late DateTime now;
  late Reachability reachability;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    reachability = Reachability(
      retryAfter: const Duration(seconds: 5),
      clock: () => now,
    );
  });

  test('starts optimistic so a healthy launch pays no probe', () {
    expect(reachability.isOnline, isTrue);
    expect(reachability.shouldShortCircuit(), isFalse);
  });

  test('a transport-level failure opens the circuit', () {
    reachability.recordAttempt();
    reachability.recordFailure();

    expect(reachability.isOffline, isTrue);
    expect(reachability.shouldShortCircuit(), isTrue,
        reason: 'the next request must fail fast, not wait out a timeout');
  });

  test('only one request per window is let through to test the water', () {
    reachability.recordFailure();

    now = now.add(const Duration(seconds: 6));
    expect(reachability.shouldShortCircuit(), isFalse,
        reason: 'half-open after retryAfter');

    // That request going out closes the window behind it.
    reachability.recordAttempt();
    expect(reachability.shouldShortCircuit(), isTrue,
        reason: 'siblings firing in the same instant must not all probe');
  });

  test('a completed round trip closes the circuit', () {
    reachability.recordFailure();
    expect(reachability.isOffline, isTrue);

    reachability.recordSuccess();

    expect(reachability.isOnline, isTrue);
    expect(reachability.shouldShortCircuit(), isFalse);
  });

  test('notifies listeners only on an actual state change', () {
    var notifications = 0;
    reachability.addListener(() => notifications++);

    reachability.recordFailure();
    reachability.recordFailure();
    expect(notifications, 1);

    reachability.recordSuccess();
    reachability.recordSuccess();
    expect(notifications, 2);
  });

  test('losing the transport goes offline without waiting for a failure', () {
    reachability.recordTransportChange(hasTransport: false);

    expect(reachability.isOffline, isTrue);
    expect(reachability.shouldShortCircuit(), isTrue);
  });

  test('joining a network clears the backoff but not the offline verdict', () {
    reachability.recordFailure();

    reachability.recordTransportChange(hasTransport: true);

    expect(reachability.isOffline, isTrue,
        reason: 'a new network may be just as dead as the old one — only a '
            'completed request proves otherwise');
    expect(reachability.shouldShortCircuit(), isFalse,
        reason: 'the next request must get an immediate attempt');
  });
}
