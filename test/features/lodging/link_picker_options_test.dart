import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/lodging/utils/link_picker_options.dart';

void main() {
  final checkIn = DateTime.now().add(const Duration(days: 30));
  final checkOut = checkIn.add(const Duration(days: 3));

  LinkOption opt(int id, String label, DateTime? date) =>
      LinkOption(id, label, date);

  group('groupLinkOptions', () {
    test('groups during / nearby / rest', () {
      final groups = groupLinkOptions([
        opt(1, 'Far', checkIn.add(const Duration(days: 60))),
        opt(2, 'During', checkIn.add(const Duration(days: 1))),
        opt(3, 'Near', checkIn.subtract(const Duration(days: 9))),
        opt(4, 'Undated', null),
      ], checkIn, checkOut);

      expect(groups.map((g) => g.label).toList(),
          ['During your stay', 'Nearby', 'Everything else']);
      expect(groups[0].options.single.id, 2);
      expect(groups[1].options.single.id, 3);
      expect(groups[2].options.map((o) => o.id).toList(), [1, 4]);
    });

    test('nearby sorted by distance from check-in', () {
      final groups = groupLinkOptions([
        opt(1, 'Nine off', checkIn.add(const Duration(days: 9))),
        opt(2, 'Two off', checkIn.subtract(const Duration(days: 2))),
      ], checkIn, checkOut);
      expect(groups.single.label, 'Nearby');
      expect(groups.single.options.map((o) => o.id).toList(), [2, 1]);
    });

    test('no check-in: single ascending group, undated last', () {
      final groups = groupLinkOptions([
        opt(1, 'B', DateTime.now().add(const Duration(days: 20))),
        opt(2, 'A', DateTime.now().add(const Duration(days: 5))),
        opt(3, 'U', null),
      ], null, null);
      expect(groups, hasLength(1));
      expect(groups.single.options.map((o) => o.id).toList(), [2, 1, 3]);
    });
  });
}
