import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/bookings_repository.dart';
import '../providers/bookings_provider.dart';
import '../widgets/contract/contract_default_view.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

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
    ref.read(cacheInvalidatorProvider).onBookingDetailChanged(
          bandId: widget.bandId,
          bookingId: widget.bookingId,
        );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // follow-up — contract-option editor isn't built yet; stub shows available
  // options so the user knows what's coming without doing anything destructive.
  Future<void> _openContractOptionPicker(BuildContext context) async {
    await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Change contract type'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {},
            child: const Text('Default contract (coming soon)'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {},
            child: const Text('External contract (coming soon)'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
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
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
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

    return detailAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Contract')),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('Contract')),
        child: SafeArea(
          child: ErrorView(message: ErrorView.friendlyMessage(e)),
        ),
      ),
      data: (booking) {
        final option = booking.contractOption ?? 'default';

        return switch (option) {
          'none' => CupertinoPageScaffold(
              navigationBar:
                  const CupertinoNavigationBar(middle: Text('Contract')),
              child: SafeArea(
                child: _NoneView(
                  onChangeType: () => _openContractOptionPicker(context),
                ),
              ),
            ),
          'external' => CupertinoPageScaffold(
              navigationBar:
                  const CupertinoNavigationBar(middle: Text('Contract')),
              child: SafeArea(
                child: _ExternalView(
                  assetUrl: booking.contract?.assetUrl,
                  uploading: _uploading,
                  onUpload: _uploadPdf,
                  onView: () => _openUrl(booking.contract!.assetUrl!),
                ),
              ),
            ),
          _ => ContractDefaultView(booking: booking),
        };
      },
    );
  }
}

// ── None mode ─────────────────────────────────────────────────────────────────

class _NoneView extends StatelessWidget {
  const _NoneView({required this.onChangeType});

  final VoidCallback onChangeType;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verbal agreement — no contract on file',
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            CupertinoButton.filled(
              onPressed: onChangeType,
              child: const Text('Change to a contract type'),
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
                color: context.secondaryText,
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
