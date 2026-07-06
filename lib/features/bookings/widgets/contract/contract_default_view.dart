import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/cache/cache_invalidator.dart';
import '../../data/bookings_repository.dart';
import '../../data/models/booking_detail.dart';
import '../../services/contract_download.dart';
import 'contract_editor.dart';
import 'contract_history_list.dart';
import 'contract_lock_banner.dart';
import 'contract_preview_webview.dart';

class ContractDefaultView extends ConsumerStatefulWidget {
  const ContractDefaultView({super.key, required this.booking});

  final BookingDetail booking;

  @override
  ConsumerState<ContractDefaultView> createState() =>
      _ContractDefaultViewState();
}

enum _LockedTab { preview, history }

class _ContractDefaultViewState extends ConsumerState<ContractDefaultView> {
  _LockedTab _tab = _LockedTab.preview;
  bool _downloading = false;
  bool _amending = false;

  bool get _isLocked {
    final s = widget.booking.status;
    return s == 'pending' || s == 'confirmed';
  }

  Future<void> _showActions() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'download'),
            child: const Text('Download PDF'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (action != 'download' || !mounted) return;

    setState(() => _downloading = true);
    try {
      await downloadAndOpenContractPdf(
        context: context,
        ref: ref,
        bandId: widget.booking.band!.id,
        bookingId: widget.booking.id,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Recall the sent contract so it can be edited and resent. Confirms
  /// first — this voids the document the client already received.
  Future<void> _amendContract() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Amend contract?'),
        content: const Text(
            'This voids the contract that is out for signature. '
            "You'll be able to edit the terms and resend it."),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Amend'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _amending = true);
    try {
      await ref.read(bookingsRepositoryProvider).amendContract(
          widget.booking.band!.id, widget.booking.id);
      // Refetch flips booking to draft, which rebuilds this view into the
      // unlocked ContractEditor.
      ref.read(cacheInvalidatorProvider).onBookingDetailChanged(
          bandId: widget.booking.band!.id, bookingId: widget.booking.id);
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Amend Failed'),
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
      if (mounted) setState(() => _amending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocked) {
      return ContractEditor(booking: widget.booking);
    }

    final envelopeId = widget.booking.contract?.envelopeId;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Contract'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _downloading ? null : _showActions,
          child: _downloading
              ? const CupertinoActivityIndicator()
              : const Icon(CupertinoIcons.ellipsis_circle),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ContractLockBanner(
                status: widget.booking.status ?? 'confirmed',
                contractOption: widget.booking.contractOption ?? 'default',
              ),
            ),
            if (widget.booking.status == 'pending' &&
                (widget.booking.contractOption ?? 'default') == 'default')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _amending ? null : _amendContract,
                    child: _amending
                        ? const CupertinoActivityIndicator()
                        : const Text('Amend contract'),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CupertinoSlidingSegmentedControl<_LockedTab>(
                groupValue: _tab,
                onValueChanged: (v) {
                  if (v != null) setState(() => _tab = v);
                },
                children: const {
                  _LockedTab.preview: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('Preview'),
                  ),
                  _LockedTab.history: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('History'),
                  ),
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_tab) {
                _LockedTab.preview => ContractPreviewWebView(
                    bandId: widget.booking.band!.id,
                    bookingId: widget.booking.id,
                  ),
                _LockedTab.history => envelopeId == null
                    ? const Center(child: Text('No PandaDoc envelope yet.'))
                    : ContractHistoryList(envelopeId: envelopeId),
              },
            ),
          ],
        ),
      ),
    );
  }
}
