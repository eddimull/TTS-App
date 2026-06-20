import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_sub.dart';
import 'package:tts_bandmate/features/personnel/data/models/call_list_entry.dart';

void main() {
  group('BandSub.fromJson', () {
    test('parses an active band sub', () {
      final sub = BandSub.fromJson({
        'id': 7,
        'type': 'band_sub',
        'status': 'active',
        'is_registered': true,
        'user_id': 42,
        'name': 'Jamie',
        'email': 'jamie@example.com',
        'band_role_id': null,
        'role_name': null,
      });

      expect(sub.id, 7);
      expect(sub.isInvitation, false);
      expect(sub.isPending, false);
      expect(sub.isRegistered, true);
      expect(sub.userId, 42);
    });

    test('parses a pending invitation', () {
      final sub = BandSub.fromJson({
        'id': 3,
        'type': 'invitation',
        'status': 'pending',
        'is_registered': false,
        'user_id': null,
        'name': 'newsub@example.com',
        'email': 'newsub@example.com',
        'band_role_id': 5,
        'role_name': 'Trumpet',
      });

      expect(sub.isInvitation, true);
      expect(sub.isPending, true);
      expect(sub.roleName, 'Trumpet');
      expect(sub.userId, isNull);
    });

    test('equality keys on id + type so invite and link never collide', () {
      final a = BandSub.fromJson(
          {'id': 1, 'type': 'band_sub', 'status': 'active', 'name': 'X'});
      final b = BandSub.fromJson(
          {'id': 1, 'type': 'invitation', 'status': 'pending', 'name': 'X'});
      expect(a == b, false);
    });
  });

  group('CallListEntry.fromJson', () {
    test('parses a roster-member entry (nested roster_member)', () {
      final entry = CallListEntry.fromJson({
        'id': 1,
        'band_id': 9,
        'instrument': 'Guitar',
        'priority': 1,
        'band_role_id': 2,
        'roster_member_id': 50,
        'roster_member': {
          'display_name': 'Pat',
          'display_email': 'pat@example.com',
          'phone': '555-1',
        },
      });

      expect(entry.isCustom, false);
      expect(entry.name, 'Pat');
      expect(entry.email, 'pat@example.com');
      expect(entry.phone, '555-1');
      expect(entry.instrument, 'Guitar');
    });

    test('parses a custom entry (custom_* fields)', () {
      final entry = CallListEntry.fromJson({
        'id': 2,
        'band_id': 9,
        'instrument': 'Drums',
        'priority': 3,
        'roster_member_id': null,
        'custom_name': 'Sam',
        'custom_email': 'sam@example.com',
        'custom_phone': '555-2',
      });

      expect(entry.isCustom, true);
      expect(entry.name, 'Sam');
      expect(entry.email, 'sam@example.com');
      expect(entry.phone, '555-2');
      expect(entry.priority, 3);
    });
  });
}
