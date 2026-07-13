import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contact_ref.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/chat/data/chat_repository.dart';

/// A reusable, read-only detail view for a single person.
///
/// Shown whenever a contact is selected anywhere in the app — a band member, a
/// substitute, a roster member, or a searched contact. Renders an avatar
/// header, name/role, and tappable email (mailto:) / phone (tel:) rows.
///
/// Optional [trailingActions] let a caller graft context-specific affordances
/// onto the canonical view — e.g. "Manage permissions" from the members list —
/// without forking the screen.
class ContactDetailScreen extends StatelessWidget {
  const ContactDetailScreen({
    super.key,
    required this.contact,
    this.trailingActions = const [],
  });

  final ContactRef contact;

  /// Extra rows appended below the contact-info section (e.g. a chevron row to
  /// open the permission editor). Each is rendered as a `CupertinoListTile`.
  final List<Widget> trailingActions;

  @override
  Widget build(BuildContext context) {
    final roleLine = _roleLine();

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Contact')),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 16),
            _Header(contact: contact, roleLine: roleLine),
            const SizedBox(height: 16),

            // ── Contact methods ─────────────────────────────────────────────
            if (contact.hasEmail || contact.hasPhone || contact.userId != null)
              CupertinoListSection.insetGrouped(
                header: const Text('Contact'),
                children: [
                  if (contact.hasEmail)
                    _ActionRow(
                      icon: CupertinoIcons.mail,
                      label: contact.email!.trim(),
                      onTap: () => _launch(
                        context,
                        Uri(scheme: 'mailto', path: contact.email!.trim()),
                      ),
                      onCopy: () => _copy(
                        context,
                        contact.email!.trim(),
                        'Email copied',
                      ),
                    ),
                  if (contact.hasPhone) ...[
                    _ActionRow(
                      icon: CupertinoIcons.phone,
                      label: contact.phone!.trim(),
                      onTap: () => _launch(
                        context,
                        Uri(scheme: 'tel', path: _telDigits(contact.phone!)),
                      ),
                      onCopy: () => _copy(
                        context,
                        contact.phone!.trim(),
                        'Phone copied',
                      ),
                    ),
                    _ActionRow(
                      icon: CupertinoIcons.chat_bubble,
                      label: 'Send Message',
                      onTap: () => _launch(
                        context,
                        Uri(scheme: 'sms', path: _telDigits(contact.phone!)),
                      ),
                    ),
                  ],
                  if (contact.userId != null)
                    _BandmateMessageRow(
                      userId: contact.userId!,
                      title: contact.name,
                    ),
                ],
              ),

            // ── Context (role / section) ────────────────────────────────────
            if ((contact.section ?? '').isNotEmpty ||
                (contact.role ?? '').isNotEmpty)
              CupertinoListSection.insetGrouped(
                header: const Text('Role'),
                children: [
                  if ((contact.section ?? '').isNotEmpty)
                    CupertinoListTile(
                      title: const Text('Section'),
                      additionalInfo: Text(contact.section!),
                    ),
                  if ((contact.role ?? '').isNotEmpty)
                    CupertinoListTile(
                      title: const Text('Instrument'),
                      additionalInfo: Text(contact.role!),
                    ),
                ],
              ),

            if (trailingActions.isNotEmpty)
              CupertinoListSection.insetGrouped(children: trailingActions),
          ],
        ),
      ),
    );
  }

  String? _roleLine() {
    final parts = <String>[
      if ((contact.role ?? '').isNotEmpty) contact.role!,
      if ((contact.section ?? '').isNotEmpty) contact.section!,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    if (contact.isOwner) return 'Owner';
    if (contact.isSub) return 'Substitute';
    return contact.subtitle;
  }

  /// Strips formatting so the `tel:` URI dials reliably; keeps a leading `+`.
  static String _telDigits(String raw) {
    final trimmed = raw.trim();
    final plus = trimmed.startsWith('+') ? '+' : '';
    return plus + trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Copies [value] to the clipboard and confirms with a brief toast-style
  /// overlay — the fallback when a contact prefers to paste the address/number
  /// elsewhere rather than launch a mail/phone app.
  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) _showCopiedToast(context, message);
  }

  void _showCopiedToast(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        bottom: MediaQuery.of(ctx).padding.bottom + 32,
        left: 0,
        right: 0,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ctx.primaryText.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    size: 18,
                    color: CupertinoColors.systemBackground.resolveFrom(ctx),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    message,
                    style: TextStyle(
                      color: CupertinoColors.systemBackground.resolveFrom(ctx),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 1400), entry.remove);
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Unavailable'),
          content: Text('Could not open ${uri.scheme} link on this device.'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.contact, required this.roleLine});

  final ContactRef contact;
  final String? roleLine;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoColors.systemBlue.resolveFrom(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            contact.initial,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          contact.name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        if ((roleLine ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            roleLine!,
            style: TextStyle(
              fontSize: 15,
              color: context.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onCopy,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// When provided, a copy button is shown as the trailing affordance (in place
  /// of the chevron) so the value can be copied without launching an app.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return CupertinoListTile(
      leading: Icon(icon, color: accent),
      title: Text(label, style: TextStyle(color: accent)),
      trailing: onCopy != null
          ? GestureDetector(
              onTap: onCopy,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  CupertinoIcons.doc_on_doc,
                  size: 20,
                  color: context.secondaryText,
                ),
              ),
            )
          : const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}

/// Opens (or creates) the in-app DM with this contact. Distinct copy from the
/// "Send Message" row above it, which launches the system SMS app.
class _BandmateMessageRow extends ConsumerStatefulWidget {
  const _BandmateMessageRow({required this.userId, required this.title});
  final int userId;
  final String title;

  @override
  ConsumerState<_BandmateMessageRow> createState() =>
      _BandmateMessageRowState();
}

class _BandmateMessageRowState extends ConsumerState<_BandmateMessageRow> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final conversation =
          await ref.read(chatRepositoryProvider).openDm(widget.userId);
      if (!mounted) return;
      context.push(
        '/conversations/${conversation.id}',
        extra: {'title': widget.title},
      );
    } catch (_) {
      if (!mounted) return;
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Couldn\'t open chat'),
          content: const Text('Check your connection and try again.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return CupertinoListTile(
      leading: _opening
          ? const CupertinoActivityIndicator(radius: 9)
          : Icon(CupertinoIcons.chat_bubble_text, color: accent),
      title: Text('Message in Bandmate', style: TextStyle(color: accent)),
      trailing: const CupertinoListTileChevron(),
      onTap: _opening ? null : _open,
    );
  }
}
