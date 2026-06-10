import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../shared/cache/cache_invalidator.dart';
import '../../data/bookings_repository.dart';
import '../../data/models/booking_detail.dart';
import '../../providers/contract_editor_provider.dart';
import '../../services/contract_download.dart';
import 'contract_fixed_header.dart';
import 'contract_send_sheet.dart';
import 'contract_signature_block.dart';
import 'contract_terms_list.dart';

class ContractEditor extends ConsumerStatefulWidget {
  const ContractEditor({
    super.key,
    required this.booking,
  });

  final BookingDetail booking;

  @override
  ConsumerState<ContractEditor> createState() => _ContractEditorState();
}

class _ContractEditorState extends ConsumerState<ContractEditor> {
  bool _editMode = true;
  bool _sending = false;
  bool _downloading = false;

  ({int bandId, int bookingId}) get _key =>
      (bandId: widget.booking.band!.id, bookingId: widget.booking.id);

  Future<void> _showMoreActions() async {
    await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _save();
            },
            child: const Text('Save'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _download();
            },
            child: const Text('Download PDF'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _save() async {
    await ref
        .read(contractEditorProvider(_key).notifier)
        .save(force: true);
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      await downloadAndOpenContractPdf(
        context: context,
        ref: ref,
        bandId: _key.bandId,
        bookingId: _key.bookingId,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _send() async {
    if (widget.booking.contacts.isEmpty || _sending) return;

    // Flush pending edits before sending.
    await ref.read(contractEditorProvider(_key).notifier).save(force: true);

    if (!mounted) return;
    final result = await showContractSendSheet(
      context,
      contacts: widget.booking.contacts,
    );
    if (result == null || !mounted) return;

    setState(() => _sending = true);
    try {
      await ref.read(bookingsRepositoryProvider).sendContract(
            _key.bandId,
            _key.bookingId,
            result.signerId,
            ccId: result.ccId,
          );
      if (!mounted) return;
      // Show the confirmation BEFORE invalidating caches. Invalidating
      // bookingDetailProvider rebuilds the screen hosting this dialog into its
      // loading state, tearing down the subtree the dialog was anchored to and
      // leaving the user on a black screen they can't dismiss. Confirm first,
      // then refresh once the user has acknowledged.
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Contract Sent'),
          content: const Text('Your contract has been sent.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      ref.read(cacheInvalidatorProvider).onBookingDetailChanged(
            bandId: _key.bandId,
            bookingId: _key.bookingId,
            contractEnvelopeId: widget.booking.contract?.envelopeId,
          );
    } catch (e) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Send failed'),
          content: Text(e.toString()),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _lastUpdatedLabel(DateTime? at) {
    if (at == null) return 'Never saved';
    return 'Last updated ${timeago.format(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final editorAsync = ref.watch(contractEditorProvider(_key));
    final hasContacts = widget.booking.contacts.isNotEmpty;

    return CupertinoPageScaffold(
      resizeToAvoidBottomInset: true,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Contract'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showMoreActions,
              child: const Icon(CupertinoIcons.ellipsis_circle),
            ),
            CupertinoButton(
              padding: const EdgeInsets.only(left: 8),
              onPressed: hasContacts && !_sending ? _send : null,
              child: _sending
                  ? const CupertinoActivityIndicator()
                  : const Text('Send',
                      style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: editorAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (state) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<bool>(
                      groupValue: _editMode,
                      onValueChanged: (v) =>
                          setState(() => _editMode = v ?? true),
                      children: const {
                        true: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text('Edit'),
                        ),
                        false: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text('Preview'),
                        ),
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          _lastUpdatedLabel(state.lastSavedAt),
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .copyWith(
                                color: CupertinoColors.secondaryLabel,
                                fontSize: 12,
                              ),
                        ),
                        if (state.unsavedChanges) ...[
                          const SizedBox(width: 8),
                          const Text('•  Unsaved',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.systemYellow)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (widget.booking.band != null)
                  SliverToBoxAdapter(
                    child: ContractFixedHeader(
                      booking: widget.booking,
                      band: widget.booking.band!,
                    ),
                  ),
                if (_editMode)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buyer name override (optional)',
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                          ),
                          const SizedBox(height: 6),
                          CupertinoTextField(
                            controller: TextEditingController(
                              text: state.buyerNameOverride ?? '',
                            )..selection = TextSelection.collapsed(
                                offset: (state.buyerNameOverride ?? '').length,
                              ),
                            placeholder: "Leave blank to use the signer's name",
                            onChanged: (v) => ref
                                .read(contractEditorProvider(_key).notifier)
                                .updateBuyerNameOverride(v),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Use when the Buyer is an organization and the signer signs on its behalf.',
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .copyWith(
                                  color: CupertinoColors.secondaryLabel,
                                  fontSize: 11,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: ContractTermsList(
                      terms: state.terms,
                      editMode: _editMode,
                      onTitleChanged: (id, v) => ref
                          .read(contractEditorProvider(_key).notifier)
                          .updateTitle(id, v),
                      onContentChanged: (id, v) => ref
                          .read(contractEditorProvider(_key).notifier)
                          .updateContent(id, v),
                      onAddSection: () => ref
                          .read(contractEditorProvider(_key).notifier)
                          .addSection(),
                      onRemoveSection: (id) => ref
                          .read(contractEditorProvider(_key).notifier)
                          .removeSection(id),
                      onReorder: (oldIdx, newIdx) => ref
                          .read(contractEditorProvider(_key).notifier)
                          .reorder(oldIdx, newIdx),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ContractSignatureBlock(
                    firstContact: widget.booking.contacts.isEmpty
                        ? null
                        : widget.booking.contacts.first,
                    buyerNameOverride: state.buyerNameOverride,
                  ),
                ),
                if (!hasContacts)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Add contacts to this booking before sending the contract.',
                        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              color: CupertinoColors.systemYellow,
                            ),
                      ),
                    ),
                  ),
                if (_downloading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                  ),
              ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
