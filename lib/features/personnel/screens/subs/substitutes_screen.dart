import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contacts/contact_detail_screen.dart';
import '../../../contacts/contact_ref.dart';
import '../../data/models/band_sub.dart';
import '../../providers/subs_provider.dart';
import 'call_lists_screen.dart';
import 'invite_sub_sheet.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Band-level substitutes hub: lists the band's subs (active + pending) and
/// links to the per-role call lists. Adding a sub here invites them to sub for
/// the band (email + accept flow).
class SubstitutesScreen extends ConsumerWidget {
  const SubstitutesScreen({super.key, required this.bandId});

  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(bandSubsProvider(bandId));

    final navBar = CupertinoNavigationBar(
      middle: const Text('Substitutes'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => _invite(context, ref),
        child: const Icon(CupertinoIcons.add),
      ),
    );

    return CupertinoPageScaffold(
      navigationBar: navBar,
      child: SafeArea(
        child: subsAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, __) => _ErrorBody(
            onRetry: () => ref.read(bandSubsProvider(bandId).notifier).refresh(),
          ),
          data: (subs) => ListView(
            children: [
              const SizedBox(height: 16),

              // ── Call lists link ─────────────────────────────────────────────
              CupertinoListSection.insetGrouped(
                children: [
                  CupertinoListTile(
                    leading: const Icon(CupertinoIcons.phone_arrow_up_right),
                    title: const Text('Call Lists'),
                    subtitle: const Text('Priority order by role'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => CallListsScreen(bandId: bandId),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Subs list ───────────────────────────────────────────────────
              if (subs.isEmpty)
                _EmptyHint(onInvite: () => _invite(context, ref))
              else
                CupertinoListSection.insetGrouped(
                  header: const Text('Subs'),
                  children: [
                    for (final sub in subs)
                      _SubRow(bandId: bandId, sub: sub),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => InviteSubSheet(bandId: bandId),
    );
  }
}

class _SubRow extends ConsumerWidget {
  const _SubRow({required this.bandId, required this.sub});

  final int bandId;
  final BandSub sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleParts = <String>[
      if (sub.roleName != null) sub.roleName!,
      if (sub.isPending) 'Invitation pending',
    ];

    final tile = CupertinoListTile(
      leading: Icon(
        sub.isPending
            ? CupertinoIcons.envelope
            : CupertinoIcons.person_crop_circle,
        color: sub.isPending
            ? CupertinoColors.systemOrange.resolveFrom(context)
            : CupertinoColors.activeBlue.resolveFrom(context),
      ),
      title: Text(sub.name.isNotEmpty ? sub.name : (sub.email ?? 'Sub')),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: const CupertinoListTileChevron(),
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ContactDetailScreen(
            contact: ContactRef(
              name: sub.name.isNotEmpty ? sub.name : (sub.email ?? 'Sub'),
              email: sub.email,
              phone: sub.phone,
              role: sub.roleName,
              userId: sub.userId,
              isSub: true,
              subtitle: sub.isPending ? 'Invitation pending' : 'Substitute',
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('${sub.type}-${sub.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRemove(context, ref),
      background: Container(
        color: CupertinoColors.destructiveRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
      ),
      child: tile,
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final isPending = sub.isPending;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(isPending ? 'Revoke Invitation' : 'Remove Sub'),
        content: Text(
          isPending
              ? 'Revoke the invitation to ${sub.email ?? sub.name}?'
              : 'Remove ${sub.name} as a sub for this band?',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isPending ? 'Revoke' : 'Remove'),
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
      await ref.read(bandSubsProvider(bandId).notifier).remove(sub);
    } catch (_) {
      if (context.mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to remove. Please try again.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }

    // The notifier filters the row out of state; keep the widget managed there.
    return false;
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onInvite});

  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Text(
            'No substitutes yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: context.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Invite someone to sub for your band. They’ll get an email to accept.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.tertiaryText,
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton.filled(
            onPressed: onInvite,
            child: const Text('Invite a Sub'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Failed to load substitutes.',
            style: TextStyle(color: context.secondaryText),
          ),
          const SizedBox(height: 12),
          CupertinoButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
