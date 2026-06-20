import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_role.dart';
import 'package:tts_bandmate/features/personnel/data/models/roster.dart';

void main() {
  group('BandRole.fromJson', () {
    test('test_parses_all_fields', () {
      final role = BandRole.fromJson({
        'id': 1,
        'name': 'Trumpet',
        'display_order': 2,
        'is_active': true,
        'roster_members_count': 3,
        'event_members_count': 5,
        'substitute_call_lists_count': 1,
      });
      expect(role.id, 1);
      expect(role.name, 'Trumpet');
      expect(role.displayOrder, 2);
      expect(role.isActive, true);
      expect(role.rosterMembersCount, 3);
      expect(role.eventMembersCount, 5);
      expect(role.substituteCallListsCount, 1);
    });

    test('test_null_coalesces_optional_fields', () {
      final role = BandRole.fromJson({'id': 2, 'name': 'Bass'});
      expect(role.displayOrder, 0);
      expect(role.isActive, true);
      expect(role.rosterMembersCount, 0);
      expect(role.eventMembersCount, 0);
      expect(role.substituteCallListsCount, 0);
    });

    test('test_copyWith_name', () {
      const role = BandRole(
        id: 1,
        name: 'Old',
        displayOrder: 0,
        isActive: true,
        rosterMembersCount: 0,
        eventMembersCount: 0,
        substituteCallListsCount: 0,
      );
      final updated = role.copyWith(name: 'New');
      expect(updated.name, 'New');
      expect(updated.id, 1);
    });

    test('test_equality_by_id', () {
      const a = BandRole(
        id: 5,
        name: 'A',
        displayOrder: 0,
        isActive: true,
        rosterMembersCount: 0,
        eventMembersCount: 0,
        substituteCallListsCount: 0,
      );
      const b = BandRole(
        id: 5,
        name: 'B',
        displayOrder: 1,
        isActive: false,
        rosterMembersCount: 1,
        eventMembersCount: 2,
        substituteCallListsCount: 3,
      );
      expect(a, b);
    });
  });

  group('RosterMember.fromJson', () {
    test('test_parses_full_member', () {
      final m = RosterMember.fromJson({
        'id': 10,
        'name': 'Jane Doe',
        'user_id': 42,
        'slot_id': 7,
        'email': 'jane@example.com',
        'phone': '555-1234',
        'role': 'Trumpet',
        'band_role_id': 3,
        'notes': 'Lead trumpet',
        'is_active': true,
        'is_user': true,
      });
      expect(m.id, 10);
      expect(m.name, 'Jane Doe');
      expect(m.userId, 42);
      expect(m.slotId, 7);
      expect(m.email, 'jane@example.com');
      expect(m.phone, '555-1234');
      expect(m.role, 'Trumpet');
      expect(m.bandRoleId, 3);
      expect(m.notes, 'Lead trumpet');
      expect(m.isActive, true);
      expect(m.isUser, true);
    });

    test('test_null_coalesces_optional_fields', () {
      final m = RosterMember.fromJson({'id': 1, 'name': 'Sub Guy'});
      expect(m.userId, isNull);
      expect(m.slotId, isNull);
      expect(m.email, isNull);
      expect(m.isActive, true);
      expect(m.isUser, false);
    });

    test('test_copyWith_isActive', () {
      const m = RosterMember(id: 1, name: 'Bob', isActive: true, isUser: false);
      final updated = m.copyWith(isActive: false);
      expect(updated.isActive, false);
      expect(m.isActive, true, reason: 'original unchanged');
    });
  });

  group('RosterSlot.fromJson', () {
    test('test_parses_slot', () {
      final s = RosterSlot.fromJson({
        'id': 5,
        'name': 'Lead Vocalist',
        'band_role_id': 2,
        'band_role_name': 'Vocals',
        'is_required': true,
        'quantity': 1,
        'notes': 'Must sight-read',
        'member_count': 1,
      });
      expect(s.id, 5);
      expect(s.name, 'Lead Vocalist');
      expect(s.bandRoleId, 2);
      expect(s.bandRoleName, 'Vocals');
      expect(s.isRequired, true);
      expect(s.quantity, 1);
      expect(s.notes, 'Must sight-read');
      expect(s.memberCount, 1);
    });

    test('test_null_coalesces_optional_fields', () {
      final s = RosterSlot.fromJson({'id': 1, 'name': 'Slot A'});
      expect(s.isRequired, false);
      expect(s.quantity, 1);
      expect(s.memberCount, 0);
      expect(s.bandRoleId, isNull);
    });
  });

  group('Roster.fromJson', () {
    test('test_parses_index_roster', () {
      final r = Roster.fromJson({
        'id': 3,
        'name': 'Full Band',
        'description': 'All members',
        'is_default': true,
        'is_active': true,
        'members_count': 12,
        'members': [],
        'slots': [],
      });
      expect(r.id, 3);
      expect(r.name, 'Full Band');
      expect(r.description, 'All members');
      expect(r.isDefault, true);
      expect(r.membersCount, 12);
    });

    test('test_parses_detail_roster_with_slots_and_members', () {
      final r = Roster.fromJson({
        'id': 1,
        'name': 'Jazz Quartet',
        'is_default': false,
        'is_active': true,
        'members_count': 0,
        'slots': [
          {'id': 10, 'name': 'Piano', 'is_required': true, 'quantity': 1, 'member_count': 1},
        ],
        'members': [
          {'id': 20, 'name': 'Alice', 'is_active': true, 'is_user': false},
        ],
      });
      expect(r.slots.length, 1);
      expect(r.slots.first.name, 'Piano');
      expect(r.members.length, 1);
      expect(r.members.first.name, 'Alice');
    });

    test('test_null_coalesces_optional_fields', () {
      final r = Roster.fromJson({'id': 1, 'name': 'Bare'});
      expect(r.isDefault, false);
      expect(r.isActive, true);
      expect(r.membersCount, 0);
      expect(r.slots, isEmpty);
      expect(r.members, isEmpty);
    });
  });
}
