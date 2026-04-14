import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_contact.dart';
import '../providers/bookings_provider.dart';

class BookingContractScreen extends ConsumerStatefulWidget {
  const BookingContractScreen({
    super.key,
    required this.bandId,
    required this.bookingId,
  });

  final int bandId;
  final int bookingId;

  @override
  ConsumerState<BookingContractScreen> createState() =>
      _BookingContractScreenState();
}

class _BookingContractScreenState
    extends ConsumerState<BookingContractScreen> {
  bool _uploading = false;

  void _invalidate() {
    ref.invalidate(bookingDetailProvider(
        (bandId: widget.bandId, bookingId: widget.bookingId)));
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _uploadPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.uploadContract(
        widget.bandId,
        widget.bookingId,
        file.bytes!,
        file.name,
      );
      _invalidate();
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(bookingDetailProvider(
        (bandId: widget.bandId, bookingId: widget.bookingId)));

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Contract'),
      ),
      child: SafeArea(
        child: detailAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => ErrorView(message: ErrorView.friendlyMessage(e)),
          data: (booking) {
            final option = booking.contractOption ?? 'default';

            return switch (option) {
              'none' => _NoneView(),
              'external' => _ExternalView(
                  assetUrl: booking.contract?.assetUrl,
                  uploading: _uploading,
                  onUpload: _uploadPdf,
                  onView: () => _openUrl(booking.contract!.assetUrl!),
                ),
              _ => _DefaultView(
                  bandId: widget.bandId,
                  bookingId: widget.bookingId,
                  contacts: booking.contacts,
                  contract: booking.contract,
                  onView: booking.contract?.assetUrl != null
                      ? () => _openUrl(booking.contract!.assetUrl!)
                      : null,
                ),
            };
          },
        ),
      ),
    );
  }
}

// ── None mode ─────────────────────────────────────────────────────────────────

class _NoneView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 64,
              color: CupertinoColors.systemGreen.resolveFrom(context),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Contract Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This booking is automatically confirmed.',
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── External mode ─────────────────────────────────────────────────────────────

class _ExternalView extends StatelessWidget {
  const _ExternalView({
    required this.assetUrl,
    required this.uploading,
    required this.onUpload,
    required this.onView,
  });

  final String? assetUrl;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (assetUrl != null) ...[
              Icon(
                CupertinoIcons.doc_checkmark,
                size: 64,
                color: CupertinoColors.systemGreen.resolveFrom(context),
              ),
              const SizedBox(height: 16),
              const Text(
                'Contract Uploaded',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: onView,
                  child: const Text('View / Download'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: uploading ? null : onUpload,
                  child: uploading
                      ? const CupertinoActivityIndicator()
                      : const Text('Replace PDF'),
                ),
              ),
            ] else ...[
              Icon(
                CupertinoIcons.doc,
                size: 64,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              const SizedBox(height: 16),
              const Text(
                'No contract uploaded yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: uploading ? null : onUpload,
                  child: uploading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CupertinoActivityIndicator(color: CupertinoColors.white),
                            SizedBox(width: 8),
                            Text('Uploading...'),
                          ],
                        )
                      : const Text('Upload Contract PDF'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Default (PandaDoc) mode ───────────────────────────────────────────────────

class _DefaultView extends ConsumerStatefulWidget {
  const _DefaultView({
    required this.bandId,
    required this.bookingId,
    required this.contacts,
    required this.contract,
    required this.onView,
  });

  final int bandId;
  final int bookingId;
  final List<BookingContact> contacts;
  final dynamic contract;
  final VoidCallback? onView;

  @override
  ConsumerState<_DefaultView> createState() => _DefaultViewState();
}

class _DefaultViewState extends ConsumerState<_DefaultView> {
  bool _sending = false;

  String get _statusLabel {
    final s = (widget.contract?.status as String?) ?? '';
    if (s.isEmpty) return 'Not sent';
    return s[0].toUpperCase() + s.substring(1);
  }

  Future<void> _pickSignerAndSend() async {
    // Index of the contact selected in the picker; default to first.
    var selectedIndex = 0;

    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => _ContactPickerSheet(
        contacts: widget.contacts,
        onIndexChanged: (i) => selectedIndex = i,
      ),
    );

    if (confirmed != true || !mounted) return;

    final signer = widget.contacts[selectedIndex];

    setState(() => _sending = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.sendContract(widget.bandId, widget.bookingId, signer.id);

      // Refresh the detail so contract status updates everywhere.
      ref.invalidate(bookingDetailProvider(
          (bandId: widget.bandId, bookingId: widget.bookingId)));

      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Contract Sent'),
            content: Text('Contract sent to ${signer.name}.'),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        final message = e.response?.data?['message'] as String? ??
            e.message ??
            e.toString();
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Send Failed'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Send Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasContacts = widget.contacts.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.doc_text,
              size: 64,
              color: CupertinoColors.systemBlue,
            ),
            const SizedBox(height: 16),
            const Text(
              'PandaDoc Contract',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // Status badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey5.resolveFrom(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusLabel,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 24),

            if (!hasContacts) ...[
              // No contacts — gate the send button and explain why.
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemYellow
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: CupertinoColors.systemYellow
                        .resolveFrom(context)
                        .withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      size: 18,
                      color: CupertinoColors.systemYellow
                          .resolveFrom(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Add contacts to this booking before sending the contract.',
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Has contacts — show the send button.
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _sending ? null : _pickSignerAndSend,
                  child: _sending
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CupertinoActivityIndicator(
                                color: CupertinoColors.white),
                            SizedBox(width: 8),
                            Text('Sending...'),
                          ],
                        )
                      : const Text('Generate & Send Contract'),
                ),
              ),
            ],

            if (widget.onView != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: widget.onView,
                  child: const Text('View / Download'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Contact picker sheet ──────────────────────────────────────────────────────

/// A bottom-sheet picker that lets the user choose a signer from [contacts].
/// Returns `true` when the user taps Done, `null`/`false` when they cancel.
class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({
    required this.contacts,
    required this.onIndexChanged,
  });

  final List<BookingContact> contacts;
  final ValueChanged<int> onIndexChanged;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: Column(
        children: [
          // Toolbar row with Cancel / Done
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CupertinoButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              CupertinoButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Expanded(
            child: CupertinoPicker(
              itemExtent: 44,
              onSelectedItemChanged: widget.onIndexChanged,
              children: widget.contacts.map((c) {
                final subtitle =
                    c.email ?? c.phone ?? c.role ?? '';
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(fontSize: 16),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
