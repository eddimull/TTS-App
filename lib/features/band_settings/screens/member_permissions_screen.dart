import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/band_member.dart';
import '../providers/band_settings_provider.dart';

class MemberPermissionsScreen extends ConsumerWidget {
  const MemberPermissionsScreen({
    super.key,
    required this.bandId,
    required this.member,
  });

  final int bandId;
  final BandMember member;

  static const _resources = [
    ('Events', 'events'),
    ('Bookings', 'bookings'),
    ('Rehearsals', 'rehearsals'),
    ('Charts', 'charts'),
    ('Songs', 'songs'),
    ('Media', 'media'),
    ('Invoices', 'invoices'),
    ('Proposals', 'proposals'),
    ('Colors', 'colors'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(bandSettingsProvider(bandId));
    final currentMember = settingsAsync.value?.members
        .where((m) => m.id == member.id)
        .firstOrNull ?? member;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(currentMember.name),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            if (currentMember.isOwner)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Owners have full access to all features.',
                  style: TextStyle(color: CupertinoColors.secondaryLabel),
                ),
              ),
            const SizedBox(height: 8),
            CupertinoListSection.insetGrouped(
              header: const Text('Permissions'),
              children: [
                for (final (label, key) in _resources) ...[
                  _PermissionRow(
                    label: '$label — Read',
                    permissionKey: 'read:$key',
                    value: currentMember.permissions['read:$key'] ?? false,
                    isOwner: currentMember.isOwner,
                    memberId: currentMember.id,
                    bandId: bandId,
                  ),
                  _PermissionRow(
                    label: '$label — Write',
                    permissionKey: 'write:$key',
                    value: currentMember.permissions['write:$key'] ?? false,
                    isOwner: currentMember.isOwner,
                    memberId: currentMember.id,
                    bandId: bandId,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends ConsumerWidget {
  const _PermissionRow({
    required this.label,
    required this.permissionKey,
    required this.value,
    required this.isOwner,
    required this.memberId,
    required this.bandId,
  });

  final String label;
  final String permissionKey;
  final bool value;
  final bool isOwner;
  final int memberId;
  final int bandId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoListTile(
      title: Text(label),
      trailing: CupertinoSwitch(
        value: isOwner ? true : value,
        onChanged: isOwner
            ? null
            : (granted) async {
                try {
                  await ref
                      .read(bandSettingsProvider(bandId).notifier)
                      .togglePermission(
                        memberId: memberId,
                        permission: permissionKey,
                        granted: granted,
                      );
                } catch (_) {
                  if (context.mounted) {
                    showCupertinoDialog<void>(
                      context: context,
                      builder: (_) => CupertinoAlertDialog(
                        title: const Text('Error'),
                        content: const Text(
                            'Failed to update permission. Please try again.'),
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
              },
      ),
    );
  }
}
