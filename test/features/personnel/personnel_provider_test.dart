import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_role.dart';
import 'package:tts_bandmate/features/personnel/data/models/band_sub.dart';
import 'package:tts_bandmate/features/personnel/data/models/call_list_entry.dart';
import 'package:tts_bandmate/features/personnel/data/models/roster.dart';
import 'package:tts_bandmate/features/personnel/data/personnel_repository.dart';
import 'package:tts_bandmate/features/personnel/providers/roles_provider.dart';
import 'package:tts_bandmate/features/personnel/providers/rosters_provider.dart';
import 'package:tts_bandmate/features/personnel/providers/subs_provider.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class FakePersonnelRepository implements PersonnelRepository {
  FakePersonnelRepository({
    this.roles = const [],
    this.rosters = const [],
    this.createRoleShouldFail = false,
    this.reorderShouldFail = false,
  });

  List<BandRole> roles;
  List<Roster> rosters;
  final bool createRoleShouldFail;
  final bool reorderShouldFail;

  String? createdRoleName;
  int? deletedRoleId;
  int? defaultRosterId;

  @override
  Future<List<BandRole>> getRoles(int bandId) async => roles;

  @override
  Future<BandRole> createRole(int bandId, {required String name}) async {
    if (createRoleShouldFail) throw Exception('Server error');
    createdRoleName = name;
    const created = BandRole(
      id: 99,
      name: 'Created',
      displayOrder: 10,
      isActive: true,
      rosterMembersCount: 0,
      eventMembersCount: 0,
      substituteCallListsCount: 0,
    );
    return created;
  }

  @override
  Future<BandRole> updateRole(int bandId, int roleId,
      {String? name, bool? isActive}) async {
    final existing = roles.firstWhere((r) => r.id == roleId);
    return existing.copyWith(name: name, isActive: isActive);
  }

  @override
  Future<void> deleteRole(int bandId, int roleId) async {
    deletedRoleId = roleId;
  }

  @override
  Future<void> reorderRoles(
      int bandId, List<({int id, int displayOrder})> order) async {
    if (reorderShouldFail) throw Exception('Server error');
  }

  @override
  Future<List<Roster>> getRosters(int bandId) async => rosters;

  @override
  Future<Roster> getRoster(int bandId, int rosterId) async =>
      rosters.firstWhere((r) => r.id == rosterId);

  @override
  Future<Roster> createRoster(int bandId,
      {required String name,
      String? description,
      bool? isDefault,
      bool? isActive}) async {
    return Roster(
        id: 88,
        name: name,
        isDefault: false,
        isActive: true,
        membersCount: 0);
  }

  @override
  Future<Roster> updateRoster(int bandId, int rosterId,
      {String? name,
      String? description,
      bool? isDefault,
      bool? isActive}) async {
    final existing = rosters.firstWhere((r) => r.id == rosterId);
    return existing.copyWith(
        name: name, description: description, isActive: isActive);
  }

  @override
  Future<void> deleteRoster(int bandId, int rosterId) async {}

  @override
  Future<void> setDefaultRoster(int bandId, int rosterId) async {
    defaultRosterId = rosterId;
  }

  @override
  Future<void> initializeRosters(int bandId) async {}

  @override
  Future<RosterSlot> createSlot(int bandId, int rosterId,
      {required String name,
      int? bandRoleId,
      bool? isRequired,
      int? quantity,
      String? notes}) async =>
      RosterSlot(
          id: 1, name: name, isRequired: false, quantity: 1, memberCount: 0);

  @override
  Future<RosterSlot> updateSlot(int bandId, int slotId,
      {String? name,
      int? bandRoleId,
      bool? isRequired,
      int? quantity,
      String? notes}) async =>
      RosterSlot(
          id: slotId, name: name ?? '', isRequired: false, quantity: 1, memberCount: 0);

  @override
  Future<void> deleteSlot(int bandId, int slotId) async {}

  @override
  Future<RosterMember> addRosterMember(int bandId, int rosterId,
      {int? userId,
      int? slotId,
      String? name,
      String? email,
      String? phone,
      String? role,
      int? bandRoleId,
      String? notes,
      bool? isActive}) async =>
      RosterMember(id: 1, name: name ?? '', isActive: true, isUser: userId != null);

  @override
  Future<RosterMember> updateRosterMember(int bandId, int memberId,
      {int? slotId,
      String? name,
      String? email,
      String? phone,
      String? role,
      int? bandRoleId,
      String? notes,
      bool? isActive}) async =>
      RosterMember(id: memberId, name: name ?? '', isActive: isActive ?? true, isUser: false);

  @override
  Future<void> removeRosterMember(int bandId, int memberId) async {}

  @override
  Future<RosterMember> toggleRosterMemberActive(
      int bandId, int memberId) async =>
      RosterMember(id: memberId, name: '', isActive: false, isUser: false);

  // ── Call lists + subs ─────────────────────────────────────────────────────

  List<CallListGroup> callLists = const [];
  List<BandSub> subs = const [];
  bool? lastSendInvite;
  String? invitedEmail;
  BandSub? removedSub;
  int? deletedCallListId;

  @override
  Future<List<CallListGroup>> getCallLists(int bandId) async => callLists;

  @override
  Future<CallListEntry> addCallListEntry(int bandId,
      {String? instrument,
      int? bandRoleId,
      int? rosterMemberId,
      String? customName,
      String? customEmail,
      String? customPhone,
      String? notes,
      bool sendInvite = true}) async {
    lastSendInvite = sendInvite;
    return CallListEntry(
      id: 1,
      bandId: bandId,
      instrument: instrument ?? '',
      priority: 1,
      name: customName,
      email: customEmail,
      phone: customPhone,
    );
  }

  @override
  Future<void> deleteCallListEntry(int bandId, int entryId) async {
    deletedCallListId = entryId;
  }

  @override
  Future<void> reorderCallList(int bandId,
      {required String instrument, required List<int> orderedIds}) async {}

  @override
  Future<List<BandSub>> getBandSubs(int bandId) async => subs;

  @override
  Future<BandSub> inviteBandSub(int bandId,
      {required String email,
      String? name,
      String? phone,
      int? bandRoleId,
      String? notes}) async {
    invitedEmail = email;
    return BandSub(
      id: 100,
      type: 'invitation',
      status: 'pending',
      isRegistered: false,
      name: name ?? email,
      email: email,
      bandRoleId: bandRoleId,
    );
  }

  @override
  Future<void> revokeBandSubInvitation(int bandId, int invitationId) async {}

  @override
  Future<void> removeBandSub(int bandId, int userId) async {}
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _role = BandRole(
  id: 1,
  name: 'Trumpet',
  displayOrder: 1,
  isActive: true,
  rosterMembersCount: 2,
  eventMembersCount: 4,
  substituteCallListsCount: 0,
);

const _roster = Roster(
  id: 10,
  name: 'Full Band',
  isDefault: false,
  isActive: true,
  membersCount: 5,
);

const _defaultRoster = Roster(
  id: 11,
  name: 'Small Combo',
  isDefault: true,
  isActive: true,
  membersCount: 3,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  ProviderContainer makeContainer(FakePersonnelRepository repo) {
    return ProviderContainer(
      overrides: [
        personnelRepositoryProvider.overrideWithValue(repo),
      ],
    );
  }

  group('RolesNotifier', () {
    test('test_build_loads_roles', () async {
      final repo = FakePersonnelRepository(roles: [_role]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final roles = await container.read(rolesProvider(1).future);
      expect(roles.length, 1);
      expect(roles.first.name, 'Trumpet');
    });

    test('test_createRole_appends_to_list', () async {
      final repo = FakePersonnelRepository(roles: [_role]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(rolesProvider(1).future);

      await container.read(rolesProvider(1).notifier).createRole('Bass');

      final roles = container.read(rolesProvider(1)).value!;
      expect(roles.length, 2);
      expect(repo.createdRoleName, 'Bass');
    });

    test('test_deleteRole_removes_from_list', () async {
      final repo = FakePersonnelRepository(roles: [_role]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(rolesProvider(1).future);

      await container.read(rolesProvider(1).notifier).deleteRole(_role.id);

      final roles = container.read(rolesProvider(1)).value!;
      expect(roles, isEmpty);
      expect(repo.deletedRoleId, _role.id);
    });

    test('test_reorderRoles_reverts_on_failure', () async {
      const a = BandRole(
        id: 1,
        name: 'A',
        displayOrder: 0,
        isActive: true,
        rosterMembersCount: 0,
        eventMembersCount: 0,
        substituteCallListsCount: 0,
      );
      const b = BandRole(
        id: 2,
        name: 'B',
        displayOrder: 1,
        isActive: true,
        rosterMembersCount: 0,
        eventMembersCount: 0,
        substituteCallListsCount: 0,
      );
      final repo =
          FakePersonnelRepository(roles: [a, b], reorderShouldFail: true);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(rolesProvider(1).future);

      await expectLater(
        container.read(rolesProvider(1).notifier).reorderRoles([b, a]),
        throwsException,
      );

      // State must be restored to the original order after the failure.
      final roles = container.read(rolesProvider(1)).value!;
      expect(roles.map((r) => r.id).toList(), [a.id, b.id]);
    });
  });

  group('RostersNotifier', () {
    test('test_build_loads_rosters', () async {
      final repo = FakePersonnelRepository(rosters: [_roster, _defaultRoster]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final rosters = await container.read(rostersProvider(1).future);
      expect(rosters.length, 2);
    });

    test('test_setDefault_marks_correct_roster', () async {
      final repo =
          FakePersonnelRepository(rosters: [_roster, _defaultRoster]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(rostersProvider(1).future);

      await container.read(rostersProvider(1).notifier).setDefault(_roster.id);

      final rosters = container.read(rostersProvider(1)).value!;
      expect(rosters.firstWhere((r) => r.id == _roster.id).isDefault, true);
      expect(rosters.firstWhere((r) => r.id == _defaultRoster.id).isDefault, false);
      expect(repo.defaultRosterId, _roster.id);
    });

    test('test_deleteRoster_removes_from_list', () async {
      final repo = FakePersonnelRepository(rosters: [_roster]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(rostersProvider(1).future);

      await container
          .read(rostersProvider(1).notifier)
          .deleteRoster(_roster.id);

      final rosters = container.read(rostersProvider(1)).value!;
      expect(rosters, isEmpty);
    });
  });

  group('BandSubsNotifier', () {
    test('test_build_loads_subs', () async {
      final repo = FakePersonnelRepository()
        ..subs = [
          const BandSub(
            id: 1,
            type: 'band_sub',
            status: 'active',
            isRegistered: true,
            name: 'Active Sub',
            userId: 5,
          ),
        ];
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      final subs = await container.read(bandSubsProvider(1).future);
      expect(subs.length, 1);
      expect(subs.first.name, 'Active Sub');
    });

    test('test_invite_passes_email_through', () async {
      final repo = FakePersonnelRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSubsProvider(1).future);

      await container
          .read(bandSubsProvider(1).notifier)
          .invite(email: 'sub@example.com', name: 'Sub');

      expect(repo.invitedEmail, 'sub@example.com');
    });

    test('test_remove_pending_invitation_filters_by_type', () async {
      const invite = BandSub(
        id: 9,
        type: 'invitation',
        status: 'pending',
        isRegistered: false,
        name: 'Pending',
      );
      final repo = FakePersonnelRepository()..subs = [invite];
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSubsProvider(1).future);

      await container.read(bandSubsProvider(1).notifier).remove(invite);

      expect(container.read(bandSubsProvider(1)).value, isEmpty);
    });
  });

  group('CallListsNotifier', () {
    test('test_addCustom_defaults_to_sending_invite', () async {
      final repo = FakePersonnelRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(callListsProvider(1).future);

      await container.read(callListsProvider(1).notifier).addCustom(
            name: 'Sam',
            email: 'sam@example.com',
            phone: '555-2',
          );

      expect(repo.lastSendInvite, true);
    });

    test('test_addCustom_can_opt_out_of_invite', () async {
      final repo = FakePersonnelRepository();
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(callListsProvider(1).future);

      await container.read(callListsProvider(1).notifier).addCustom(
            name: 'Sam',
            email: 'sam@example.com',
            phone: '555-2',
            sendInvite: false,
          );

      expect(repo.lastSendInvite, false);
    });
  });
}
