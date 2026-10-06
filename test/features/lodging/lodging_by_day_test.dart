import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/utils/lodging_by_day.dart';

// Pinned mid-morning in June: the fixtures below offset from now by whole days
// plus 15h, so a wall-clock pin keeps every stay on the intended calendar days
// (no midnight spill, no DST transition inside a stay).
final _pinned = DateTime(2026, 6, 15, 10);

/// Runs [body] with `clock.now()` fixed at [_pinned].
T _atPinned<T>(T Function() body) => withClock(Clock.fixed(_pinned), body);

LodgingSummary _stay(int id, DateTime checkIn, DateTime checkOut) =>
    LodgingSummary(
      id: id,
      name: 'Stay $id',
      checkInAt: checkIn.toIso8601String(),
      checkOutAt: checkOut.toIso8601String(),
      roomCount: 1,
      attachmentCount: 0,
    );

void main() {
  test('expands inclusive day range with boundary flags', () => _atPinned(() {
    final checkIn = clock.now().add(const Duration(days: 10, hours: 15));
    final checkOut = checkIn.add(const Duration(days: 2)); // 3 covered days
    final map = lodgingByDay([_stay(1, checkIn, checkOut)]);

    expect(map, hasLength(3));
    final firstDay = DateTime(checkIn.year, checkIn.month, checkIn.day);
    expect(map[firstDay]!.single.isCheckIn, isTrue);
    expect(map[firstDay]!.single.isCheckOut, isFalse);
    final midDay = firstDay.add(const Duration(days: 1));
    expect(map[midDay]!.single.isCheckIn, isFalse);
    expect(map[midDay]!.single.isCheckOut, isFalse);
    final lastDay = firstDay.add(const Duration(days: 2));
    expect(map[lastDay]!.single.isCheckOut, isTrue);
  }));

  test('overlapping stays stack on shared days', () => _atPinned(() {
    final a = clock.now().add(const Duration(days: 5, hours: 15));
    final map = lodgingByDay([
      _stay(1, a, a.add(const Duration(days: 2))),
      _stay(2, a.add(const Duration(days: 1)), a.add(const Duration(days: 3))),
    ]);
    final sharedDay = DateTime(a.year, a.month, a.day).add(const Duration(days: 1));
    expect(map[sharedDay], hasLength(2));
  }));

  test('same-day stay flags both boundaries; malformed dates skipped', () => _atPinned(() {
    final a = clock.now().add(const Duration(days: 4, hours: 15));
    final map = lodgingByDay([
      _stay(1, a, a.add(const Duration(hours: 2))),
      const LodgingSummary(
          id: 9, name: 'Broken', checkInAt: 'garbage', checkOutAt: '',
          roomCount: 0, attachmentCount: 0),
    ]);
    expect(map, hasLength(1));
    expect(map.values.single.single.isCheckIn, isTrue);
    expect(map.values.single.single.isCheckOut, isTrue);
  }));

  test('stay across a DST change keeps midnight day keys and flags checkout',
      () {
    // US clocks fall back on 2026-11-01. Stepping by a 24h Duration from
    // Nov 1 00:00 lands on Nov 1 23:00, so later days lost their midnight
    // key and checkout was never flagged. In a timezone without DST this
    // passes trivially.
    final checkIn = DateTime(2026, 10, 31, 15);
    final checkOut = DateTime(2026, 11, 3, 11);
    final map = lodgingByDay([_stay(1, checkIn, checkOut)]);

    expect(map.keys, [
      DateTime(2026, 10, 31),
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 2),
      DateTime(2026, 11, 3),
    ]);
    expect(map[DateTime(2026, 11, 3)]!.single.isCheckOut, isTrue);
  });
}
