import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/bookings_repository.dart';
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
          error: (e, _) => Center(child: Text('Error: $e')),
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

class _DefaultView extends StatelessWidget {
  const _DefaultView({
    required this.contract,
    required this.onView,
  });

  final dynamic contract;
  final VoidCallback? onView;

  String get _statusLabel {
    final s = (contract?.status as String?) ?? '';
    if (s.isEmpty) return 'Not sent';
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            const SizedBox(height: 16),
            Text(
              'Contract is managed via PandaDoc. Use the web app to send or review.',
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              textAlign: TextAlign.center,
            ),
            if (onView != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: onView,
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
