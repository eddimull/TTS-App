import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../data/models/band_invitation.dart';
import '../data/models/band_member.dart';
import '../providers/band_settings_provider.dart';
import 'band_info_edit_screen.dart';
import 'member_permissions_screen.dart';
import 'widgets/invite_section.dart';

class BandSettingsScreen extends ConsumerWidget {
  const BandSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandId = ref.watch(selectedBandProvider).value;

    const navBar = CupertinoNavigationBar(middle: Text('Band Settings'));

    if (bandId == null) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    final settingsAsync = ref.watch(bandSettingsProvider(bandId));

    if (settingsAsync.isLoading && !settingsAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    if (settingsAsync.hasError && !settingsAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load band settings. Please try again.',
              style: TextStyle(color: CupertinoColors.secondaryLabel),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final settings = settingsAsync.value!;

    return CupertinoPageScaffold(
      navigationBar: navBar,
      child: SafeArea(
        child: ListView(
          children: [
            // ── Section 1: Band Info ──────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('Band Info'),
              children: [
                CupertinoListTile(
                  leading: _BandLogo(logoUrl: settings.detail.logoUrl),
                  title: Text(settings.detail.name),
                  subtitle: Text(settings.detail.siteName),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => BandInfoEditScreen(
                        bandId: bandId,
                        initial: settings.detail,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── Section 2: Members ────────────────────────────────────────────
            CupertinoListSection.insetGrouped(
              header: const Text('Members'),
              children: [
                for (final member in settings.members)
                  _MemberRow(member: member, bandId: bandId),
              ],
            ),

            // ── Section 3: Pending Invitations (conditional) ──────────────────
            if (settings.invitations.isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: const Text('Pending Invitations'),
                children: [
                  for (final invite in settings.invitations)
                    _InvitationRow(invite: invite, bandId: bandId),
                ],
              ),

            // ── Section 4: Invite ─────────────────────────────────────────────
            InviteSection(bandId: bandId),
          ],
        ),
      ),
    );
  }
}

// ── Band logo avatar ──────────────────────────────────────────────────────────

/// Circular logo badge for the band info tile.
/// Uses ClipOval + Container to avoid the Material CircleAvatar widget.
class _BandLogo extends StatelessWidget {
  const _BandLogo({required this.logoUrl});

  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: 36,
        height: 36,
        color: CupertinoColors.systemGrey5,
        child: logoUrl != null
            ? Image.network(
                logoUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              )
            : const Icon(
                CupertinoIcons.music_note,
                size: 16,
                color: CupertinoColors.systemGrey,
              ),
      ),
    );
  }
}

// ── Member row ────────────────────────────────────────────────────────────────

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member, required this.bandId});

  final BandMember member;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initial letter avatar, Cupertino-safe (no CircleAvatar).
    final avatar = ClipOval(
      child: Container(
        width: 36,
        height: 36,
        color: CupertinoColors.systemGrey4,
        alignment: Alignment.center,
        child: Text(
          member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: CupertinoColors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );

    final tile = CupertinoListTile(
      leading: avatar,
      title: Text(member.name),
      subtitle: Text(member.isOwner ? 'Owner' : 'Member'),
      trailing: const CupertinoListTileChevron(),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => MemberPermissionsScreen(
            bandId: bandId,
            member: member,
          ),
        ),
      ),
    );

    // Owners cannot be removed — disable swipe entirely.
    if (member.isOwner) {
      return Dismissible(
        key: ValueKey('member-${member.id}'),
        direction: DismissDirection.none,
        child: tile,
      );
    }

    return Dismissible(
      key: ValueKey('member-${member.id}'),
      direction: DismissDirection.endToStart,
      // The notifier updates state directly; we never let Dismissible remove
      // the widget itself — return false to keep widget management in the provider.
      confirmDismiss: (_) => _confirmRemoveMember(context, ref),
      background: _deleteBackground(),
      child: tile,
    );
  }

  Future<bool?> _confirmRemoveMember(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from the band?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await ref
          .read(bandSettingsProvider(bandId).notifier)
          .removeMember(bandId: bandId, userId: member.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text(
                'Failed to remove member. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    }

    // Always return false — the notifier filtered the member out of state,
    // so the list rebuilds without this widget on its own.
    return false;
  }

  Widget _deleteBackground() {
    return Container(
      color: CupertinoColors.destructiveRed,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(
        CupertinoIcons.delete,
        color: CupertinoColors.white,
      ),
    );
  }
}

// ── Invitation row ────────────────────────────────────────────────────────────

class _InvitationRow extends ConsumerWidget {
  const _InvitationRow({required this.invite, required this.bandId});

  final BandInvitation invite;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = CupertinoListTile(
      leading: const Icon(CupertinoIcons.envelope),
      title: Text(invite.email),
      subtitle: Text(
        invite.inviteType == 'owner' ? 'Owner invite' : 'Member invite',
      ),
    );

    return Dismissible(
      key: ValueKey('invite-${invite.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRevokeInvite(context, ref),
      background: _deleteBackground(),
      child: tile,
    );
  }

  Future<bool?> _confirmRevokeInvite(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Revoke Invitation'),
        content: Text('Revoke invite to ${invite.email}?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await ref
          .read(bandSettingsProvider(bandId).notifier)
          .revokeInvitation(bandId: bandId, invitationId: invite.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text(
                'Failed to revoke invitation. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    }

    // Always return false — the notifier removes the invite from state,
    // so the list rebuilds without this widget on its own.
    return false;
  }

  Widget _deleteBackground() {
    return Container(
      color: CupertinoColors.destructiveRed,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(
        CupertinoIcons.delete,
        color: CupertinoColors.white,
      ),
    );
  }
}
