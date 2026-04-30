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
    if (!email.contains('@')) {
      showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Invalid Email'),
          content: const Text('Please enter a valid email address.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
      return;
    }
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
    Navigator.of(context, rootNavigator: true).push<void>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => _QrFullScreen(inviteKey: key),
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

class _QrFullScreen extends StatelessWidget {
  const _QrFullScreen({required this.inviteKey});

  final String inviteKey;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Invite QR Code'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Share.share(inviteKey),
          child: const Icon(CupertinoIcons.share),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest.shortestSide;
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        color: CupertinoColors.white,
                        child: QrImageView(
                          data: inviteKey,
                          size: size - 32,
                          backgroundColor: CupertinoColors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Anyone with this code can join your band.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
