import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/data/models/lodging.dart';
import 'package:tts_bandmate/features/lodging/utils/lodging_by_day.dart';

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
  test('expands inclusive day range with boundary flags', () {
    final checkIn = DateTime.now().add(const Duration(days: 10, hours: 15));
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
  });

  test('overlapping stays stack on shared days', () {
    final a = DateTime.now().add(const Duration(days: 5, hours: 15));
    final map = lodgingByDay([
      _stay(1, a, a.add(const Duration(days: 2))),
      _stay(2, a.add(const Duration(days: 1)), a.add(const Duration(days: 3))),
    ]);
    final sharedDay = DateTime(a.year, a.month, a.day).add(const Duration(days: 1));
    expect(map[sharedDay], hasLength(2));
  });

  test('same-day stay flags both boundaries; malformed dates skipped', () {
    final a = DateTime.now().add(const Duration(days: 4, hours: 15));
    final map = lodgingByDay([
      _stay(1, a, a.add(const Duration(hours: 2))),
      const LodgingSummary(
          id: 9, name: 'Broken', checkInAt: 'garbage', checkOutAt: '',
          roomCount: 0, attachmentCount: 0),
    ]);
    expect(map, hasLength(1));
    expect(map.values.single.single.isCheckIn, isTrue);
    expect(map.values.single.single.isCheckOut, isTrue);
  });
}
