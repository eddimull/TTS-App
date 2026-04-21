import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/band_settings/data/band_settings_repository.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_detail.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_invitation.dart';
import 'package:tts_bandmate/features/band_settings/data/models/band_member.dart';
import 'package:tts_bandmate/features/band_settings/providers/band_settings_provider.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class FakeBandSettingsRepository implements BandSettingsRepository {
  FakeBandSettingsRepository({
    this.detail,
    this.members = const [],
    this.invitations = const [],
    this.setPermissionShouldFail = false,
  });

  final BandDetail? detail;
  final List<BandMember> members;
  final List<BandInvitation> invitations;
  final bool setPermissionShouldFail;

  String? lastPermission;
  bool? lastGranted;
  int? removedMemberId;
  int? revokedInvitationId;

  @override
  Future<BandDetail> getBandDetail(int bandId) async =>
      detail ??
      const BandDetail(
          id: 10,
          name: 'Test Band',
          siteName: 'test-band',
          address: '',
          city: '',
          state: '',
          zip: '');

  @override
  Future<void> updateBandDetail(int bandId,
      {required String name,
      required String siteName,
      required String address,
      required String city,
      required String state,
      required String zip}) async {}

  @override
  Future<void> uploadLogo(int bandId, List<int> bytes, String filename) async {}

  @override
  Future<List<BandMember>> getMembers(int bandId) async => members;

  @override
  Future<void> removeMember(int bandId, int userId) async {
    removedMemberId = userId;
  }

  @override
  Future<void> setPermission(int bandId, int userId,
      {required String permission, required bool granted}) async {
    if (setPermissionShouldFail) throw Exception('Server error');
    lastPermission = permission;
    lastGranted = granted;
  }

  @override
  Future<List<BandInvitation>> getInvitations(int bandId) async => invitations;

  @override
  Future<void> revokeInvitation(int bandId, int invitationId) async {
    revokedInvitationId = invitationId;
  }
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _member = BandMember(
  id: 5,
  name: 'Jane',
  isOwner: false,
  permissions: {'read:events': false},
);

const _invite = BandInvitation(
  id: 99,
  email: 'new@example.com',
  inviteType: 'member',
  key: 'abc-123',
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('BandSettingsNotifier', () {
    ProviderContainer makeContainer(FakeBandSettingsRepository repo) {
      return ProviderContainer(
        overrides: [
          bandSettingsRepositoryProvider.overrideWithValue(repo),
        ],
      );
    }

    test('test_load_populates_state', () async {
      final repo = FakeBandSettingsRepository(
        members: [_member],
        invitations: [_invite],
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);

      await container.read(bandSettingsProvider(10).notifier).load();

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.detail.name, 'Test Band');
      expect(state.members.length, 1);
      expect(state.invitations.length, 1);
    });

    test('test_togglePermission_optimistically_updates_and_calls_repo',
        () async {
      final repo = FakeBandSettingsRepository(members: [_member]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      await container
          .read(bandSettingsProvider(10).notifier)
          .togglePermission(memberId: 5, permission: 'read:events', granted: true);

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.members.first.permissions['read:events'], true);
      expect(repo.lastPermission, 'read:events');
      expect(repo.lastGranted, true);
    });

    test('test_togglePermission_reverts_on_api_failure', () async {
      final repo = FakeBandSettingsRepository(
        members: [_member],
        setPermissionShouldFail: true,
      );
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      Object? caughtError;
      try {
        await container
            .read(bandSettingsProvider(10).notifier)
            .togglePermission(
                memberId: 5, permission: 'read:events', granted: true);
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isNotNull);
      final state = container.read(bandSettingsProvider(10)).value!;
      // Should have reverted to false
      expect(state.members.first.permissions['read:events'], false);
    });

    test('test_removeMember_removes_from_local_state', () async {
      final repo = FakeBandSettingsRepository(members: [_member]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      await container
          .read(bandSettingsProvider(10).notifier)
          .removeMember(userId: 5);

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.members, isEmpty);
      expect(repo.removedMemberId, 5);
    });

    test('test_revokeInvitation_removes_from_local_state', () async {
      final repo = FakeBandSettingsRepository(invitations: [_invite]);
      final container = makeContainer(repo);
      addTearDown(container.dispose);
      await container.read(bandSettingsProvider(10).notifier).load();

      await container
          .read(bandSettingsProvider(10).notifier)
          .revokeInvitation(invitationId: 99);

      final state = container.read(bandSettingsProvider(10)).value!;
      expect(state.invitations, isEmpty);
      expect(repo.revokedInvitationId, 99);
    });
  });
}
