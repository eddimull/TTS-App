import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/band_settings_provider.dart';
import '../../../bands/providers/bands_provider.dart';

class InviteSection extends ConsumerStatefulWidget {
  const InviteSection({super.key, required this.bandId});

  final int bandId;

  @override
  ConsumerState<InviteSection> createState() => _InviteSectionState();
}

class _InviteSectionState extends ConsumerState<InviteSection> {
  bool _expanded = false;
  final _emailController = TextEditingController();
  int _selectedType = 1; // 0 = owner, 1 = member
  bool _sending = false;
  String? _inviteKey;

  @override
  void initState() {
    super.initState();
    _loadInviteKey();
  }

  Future<void> _loadInviteKey() async {
    try {
      final key = await ref
          .read(bandsRepositoryProvider)
          .getInviteKey(widget.bandId);
      if (mounted) setState(() => _inviteKey = key);
    } catch (_) {
      // QR row simply stays hidden if the key cannot be fetched.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendInvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _sending = true);
    try {
      // NOTE: BandsRepository.inviteMembers takes only emails — the role
      // segmented control is presented in the UI but the current API does not
      // accept a role parameter. Wire it here once the endpoint supports it.
      await ref
          .read(bandsRepositoryProvider)
          .inviteMembers(widget.bandId, [email]);
      _emailController.clear();
      setState(() => _expanded = false);
      // Reload the invitations list so the parent screen stays in sync.
      await ref
          .read(bandSettingsProvider(widget.bandId).notifier)
          .load();
    } catch (_) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to send invite. Please try again.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showQrModal() {
    if (_inviteKey == null) return;
    final key = _inviteKey!;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('Invite QR Code'),
        message: Column(
          children: [
            // Fixed size keeps the sheet from expanding unpredictably.
            QrImageView(data: key, size: 200),
            const SizedBox(height: 8),
            const Text('Anyone with this code can join your band.'),
          ],
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Share.share(key);
              Navigator.of(context).pop();
            },
            child: const Text('Share Code'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      header: const Text('Invite'),
      children: [
        // ── Expandable invite row ──────────────────────────────────────────
        CupertinoListTile(
          title: const Text('Invite a Member'),
          trailing: Icon(
            _expanded
                ? CupertinoIcons.chevron_up
                : CupertinoIcons.chevron_down,
            size: 16,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          // Padding widget sits inside the list section as a plain tile.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CupertinoTextField(
                  controller: _emailController,
                  placeholder: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 8),
                CupertinoSlidingSegmentedControl<int>(
                  groupValue: _selectedType,
                  onValueChanged: (v) =>
                      setState(() => _selectedType = v ?? 1),
                  children: const {
                    0: Text('Owner'),
                    1: Text('Member'),
                  },
                ),
                const SizedBox(height: 12),
                CupertinoButton.filled(
                  onPressed: _sending ? null : _sendInvite,
                  child: _sending
                      ? const CupertinoActivityIndicator()
                      : const Text('Send Invite'),
                ),
              ],
            ),
          ),

        // ── QR row — only shown once the key has been fetched ─────────────
        if (_inviteKey != null)
          CupertinoListTile(
            title: const Text('Show QR Code'),
            leading: const Icon(CupertinoIcons.qrcode),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
            onTap: _showQrModal,
          ),
      ],
    );
  }
}
