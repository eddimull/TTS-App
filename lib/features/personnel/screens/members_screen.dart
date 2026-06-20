import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/band_settings/data/models/band_invitation.dart';
import '../../../features/band_settings/data/models/band_member.dart';
import '../../../features/band_settings/providers/band_settings_provider.dart';
import '../../../features/band_settings/screens/member_permissions_screen.dart';
import '../../../features/band_settings/screens/widgets/invite_section.dart';
import '../../../features/contacts/contact_detail_screen.dart';
import '../../../features/contacts/contact_ref.dart';

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const navBar = CupertinoNavigationBar(middle: Text('Members'));
    final settingsAsync = ref.watch(bandSettingsProvider(bandId));

    if (settingsAsync.isLoading && !settingsAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(child: Center(child: CupertinoActivityIndicator())),
      );
    }

    if (settingsAsync.hasError && !settingsAsync.hasValue) {
      return const CupertinoPageScaffold(
        navigationBar: navBar,
        child: SafeArea(
          child: Center(
            child: Text(
              'Failed to load members. Please try again.',
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
            CupertinoListSection.insetGrouped(
              header: const Text('Members'),
              children: [
                for (final member in settings.members)
                  _MemberRow(member: member, bandId: bandId),
              ],
            ),
            if (settings.invitations.isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: const Text('Pending Invitations'),
                children: [
                  for (final invite in settings.invitations)
                    _InvitationRow(invite: invite, bandId: bandId),
                ],
              ),
            InviteSection(bandId: bandId),
          ],
        ),
      ),
    );
  }
}

Widget _swipeDeleteBackground() => Container(
      color: CupertinoColors.destructiveRed,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
    );

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member, required this.bandId});

  final BandMember member;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          builder: (_) => ContactDetailScreen(
            contact: ContactRef(
              name: member.name,
              email: member.email,
              isOwner: member.isOwner,
              userId: member.id,
              subtitle: member.isOwner ? 'Owner' : 'Member',
            ),
            trailingActions: [
              CupertinoListTile(
                title: const Text('Manage Permissions'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => MemberPermissionsScreen(
                      bandId: bandId,
                      member: member,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

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
      confirmDismiss: (_) => _confirmRemoveMember(context, ref),
      background: _swipeDeleteBackground(),
      child: tile,
    );
  }

  Future<bool?> _confirmRemoveMember(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.name} from the band?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return false;

    try {
      await ref
          .read(bandSettingsProvider(bandId).notifier)
          .removeMember(userId: member.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to remove member. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      }
    }
    return false;
  }
}

class _InvitationRow extends ConsumerWidget {
  const _InvitationRow({required this.invite, required this.bandId});

  final BandInvitation invite;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = CupertinoListTile(
      leading: const Icon(CupertinoIcons.envelope),
      title: Text(invite.email ?? 'Shareable invite link'),
      subtitle: Text(
        invite.inviteType == 'owner' ? 'Owner invite' : 'Member invite',
      ),
    );

    return Dismissible(
      key: ValueKey('invite-${invite.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRevokeInvite(context, ref),
      background: _swipeDeleteBackground(),
      child: tile,
    );
  }

  Future<bool?> _confirmRevokeInvite(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Revoke Invitation'),
        content: Text(
            'Revoke invite to ${invite.email ?? 'this shareable link'}?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return false;

    try {
      await ref
          .read(bandSettingsProvider(bandId).notifier)
          .revokeInvitation(invitationId: invite.id);
    } catch (_) {
      if (context.mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text(
                'Failed to revoke invitation. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      }
    }
    return false;
  }
}
