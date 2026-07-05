import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/widgets/band_identity_chip.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:tts_bandmate/shared/widgets/status_chip.dart';
import 'package:tts_bandmate/shared/cache/cache_invalidator.dart';
import '../../events/data/models/event_summary.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_contact.dart';
import '../data/models/booking_detail.dart';
import '../providers/bookings_provider.dart';
import '../widgets/booking_contract_nudge.dart';
import '../widgets/booking_engagement_summary.dart';
import '../widgets/booking_section_tile.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({
    super.key,
    required this.bandId,
    required this.bookingId,
  });

  final int bandId;
  final int bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (bandId: bandId, bookingId: bookingId);
    final detailAsync = ref.watch(bookingDetailProvider(args));

    return detailAsync.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.invalidate(bookingDetailProvider(args)),
        ),
      ),
      data: (booking) => _BookingDetailView(
        bandId: bandId,
        bookingId: bookingId,
        booking: booking,
      ),
    );
  }
}

class _BookingDetailView extends ConsumerStatefulWidget {
  const _BookingDetailView({
    required this.bandId,
    required this.bookingId,
    required this.booking,
  });

  final int bandId;
  final int bookingId;
  final BookingDetail booking;

  @override
  ConsumerState<_BookingDetailView> createState() =>
      _BookingDetailViewState();
}

class _BookingDetailViewState extends ConsumerState<_BookingDetailView> {
  bool _isActioning = false;

  // ── Action sheet ─────────────────────────────────────────────────────────────

  void _showActions(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              context.push(
                '/bookings/${widget.bandId}/${widget.bookingId}/edit',
                extra: widget.booking,
              );
            },
            child: const Text('Edit'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              _confirmCancel();
            },
            child: const Text('Cancel Booking'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(context).pop();
              _confirmDelete();
            },
            child: const Text('Delete Booking'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
            'Are you sure you want to cancel this booking? This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isActioning = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.cancelBooking(widget.bandId, widget.bookingId);
      if (!mounted) return;
      ref.read(cacheInvalidatorProvider).onBookingChanged(
            bandId: widget.bandId,
            bookingId: widget.bookingId,
          );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('Could not cancel booking.\n$e');
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete Booking'),
        content: const Text(
            'This will permanently delete the booking. Are you sure?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isActioning = true);
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      await repo.deleteBooking(widget.bandId, widget.bookingId);
      if (!mounted) return;
      ref.read(cacheInvalidatorProvider).onBookingDeleted(
            bandId: widget.bandId,
            bookingId: widget.bookingId,
          );
      context.go('/bookings');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActioning = false);
      _showErrorDialog('Could not delete booking.\n$e');
    }
  }

  void _showErrorDialog(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _paymentsSubtitle(BookingDetail b) {
    if (b.payments.isEmpty) return 'No payments recorded';
    final paid = b.displayAmountPaid;
    final total = b.displayPrice;
    return '$paid paid of $total';
  }

  String _contractSubtitle(BookingDetail b) {
    final option = b.contractOption;
    if (option == 'none') return 'No contract required';
    if (b.contract != null && b.contract!.status != null) {
      return _capitalise(b.contract!.status!);
    }
    return option != null ? _capitalise(option) : 'Not configured';
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── Events section ────────────────────────────────────────────────────────

  String _formatEventDate(String iso) {
    try {
      return DateFormat('EEE M/d').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  String _eventCardSubtitle(EventSummary e) {
    final parts = <String>[];
    parts.add(_formatEventDate(e.date));
    if (e.startTime != null && e.startTime!.isNotEmpty) {
      if (e.endTime != null && e.endTime!.isNotEmpty) {
        parts.add('${e.startTime} – ${e.endTime}');
      } else {
        parts.add(e.startTime!);
      }
    }
    if (e.venueName != null && e.venueName!.isNotEmpty) {
      parts.add(e.venueName!);
    }
    return parts.join(' · ');
  }

  Widget _eventCard(EventSummary e) {
    return GestureDetector(
      onTap: () => context.push(
        '/events/${e.key}',
        extra: {
          'parentBookingName': widget.booking.name,
          'parentBookingId': widget.booking.id,
          'parentBandId': widget.bandId,
        },
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _eventCardSubtitle(e),
                    style: TextStyle(
                      color: context.secondaryText,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: context.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventsSection(BookingDetail booking) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Events',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          const SizedBox(height: 8),
          ...booking.events.map((e) => _eventCard(e)),
          CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Text('+ Add event'),
            onPressed: () {
              context.push(
                '/bookings/${widget.bandId}/${widget.bookingId}/edit',
                extra: widget.booking,
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Itemization summary ───────────────────────────────────────────────────

  Widget? _itemizationSummary(BookingDetail booking) {
    if (!booking.isMultiEvent) return null;
    final hasPrice = booking.events.any(
      (e) => e.price != null && (double.tryParse(e.price!) ?? 0) > 0,
    );
    if (!hasPrice) return null;

    final total = double.tryParse(booking.price ?? '') ?? 0;
    final allocated = booking.events.fold<double>(
      0,
      (sum, e) => sum + (double.tryParse(e.price ?? '') ?? 0),
    );
    final unallocated = total - allocated;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Itemization',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          const SizedBox(height: 8),
          Text('Total: \$${total.toStringAsFixed(2)}'),
          ...booking.events
              .where((e) => (double.tryParse(e.price ?? '') ?? 0) > 0)
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_formatEventDate(e.date)} — \$${e.price}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
          if (unallocated.abs() > 0.01)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Other / Unallocated: \$${unallocated.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final itemization = _itemizationSummary(b);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(b.name),
        trailing: _isActioning
            ? const CupertinoActivityIndicator()
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showActions(context),
                child: const Icon(CupertinoIcons.ellipsis_circle),
              ),
      ),
      child: CustomScrollView(
        slivers: [
          SliverSafeArea(
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Band identity ─────────────────────────────────────────
                // Shows "Personal + user avatar" for personal gigs; band
                // name + logo for regular band bookings. Omitted when the
                // backend hasn't yet returned a band payload (legacy cache).
                if (b.band != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: BandIdentityChip(
                      band: b.band!,
                      size: 22,
                    ),
                  ),
                ],

                // ── Engagement summary strip ───────────────────────────────
                const SizedBox(height: 8),
                BookingEngagementSummary(booking: b),

                // ── Status row ────────────────────────────────────────────
                if (b.status != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: StatusChip(status: b.status!),
                  ),
                ],

                // ── Contract next-step nudge ──────────────────────────────
                BookingContractNudge(
                  booking: b,
                  onAddContact: () => context.push(
                      '/bookings/${widget.bandId}/${widget.bookingId}/contacts'),
                  onSendContract: () => context.push(
                      '/bookings/${widget.bandId}/${widget.bookingId}/contract'),
                ),

                // ── Financial summary ─────────────────────────────────────
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _FinancialsCard(booking: b),
                ),

                // ── Events section ────────────────────────────────────────
                const SizedBox(height: 16),
                const _SectionHeader(label: 'Events'),
                _eventsSection(b),

                // ── Itemization summary ───────────────────────────────────
                if (itemization != null) ...[
                  const SizedBox(height: 8),
                  const _SectionHeader(label: 'Itemization'),
                  itemization,
                ],

                // ── Section tiles ─────────────────────────────────────────
                const SizedBox(height: 24),
                const _SectionHeader(label: 'Payments'),
                BookingSectionTile(
                  icon: CupertinoIcons.money_dollar_circle,
                  title: 'Payments',
                  subtitle: _paymentsSubtitle(b),
                  onTap: () => context.push(
                      '/bookings/${widget.bandId}/${widget.bookingId}/payments'),
                ),
                if ((double.tryParse(b.price ?? '') ?? 0) > 0)
                  BookingSectionTile(
                    icon: CupertinoIcons.chart_pie,
                    title: 'Payout',
                    subtitle: 'Member breakdown across performances',
                    onTap: () => context.push(
                        '/bookings/${widget.bandId}/${widget.bookingId}/payout'),
                  ),

                // ── Inline contacts preview ───────────────────────────────
                const SizedBox(height: 16),
                const _SectionHeader(label: 'Contacts'),
                if (b.contacts.isNotEmpty) ...[
                  ...b.contacts.take(2).map((c) => _InlineContactRow(contact: c)),
                ],
                BookingSectionTile(
                  icon: CupertinoIcons.person_2,
                  title: 'All Contacts',
                  subtitle: '${b.contacts.length} contact${b.contacts.length == 1 ? '' : 's'}',
                  onTap: () => context.push(
                      '/bookings/${widget.bandId}/${widget.bookingId}/contacts'),
                ),

                // ── Contract ──────────────────────────────────────────────
                const SizedBox(height: 16),
                const _SectionHeader(label: 'Contract'),
                BookingSectionTile(
                  icon: CupertinoIcons.doc_text,
                  title: 'Contract',
                  subtitle: _contractSubtitle(b),
                  onTap: () => context.push(
                      '/bookings/${widget.bandId}/${widget.bookingId}/contract'),
                ),

                // ── Notes ─────────────────────────────────────────────────
                if (b.notes != null && b.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _SectionHeader(label: 'Notes'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(b.notes!,
                          style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                ],

                // ── History ───────────────────────────────────────────────
                const SizedBox(height: 16),
                const _SectionHeader(label: 'History'),
                BookingSectionTile(
                  icon: CupertinoIcons.clock,
                  title: 'History',
                  onTap: () => context.push(
                      '/bookings/${widget.bandId}/${widget.bookingId}/history'),
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.secondaryText,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FinancialsCard extends StatelessWidget {
  const _FinancialsCard({required this.booking});
  final BookingDetail booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _FinanceRow(label: 'Total', value: booking.displayPrice, bold: true),
          const SizedBox(height: 6),
          _FinanceRow(
            label: 'Paid',
            value: booking.displayAmountPaid,
            valueColor: CupertinoColors.systemGreen.resolveFrom(context),
          ),
          const SizedBox(height: 6),
          _FinanceRow(
            label: 'Balance due',
            value: booking.displayAmountDue,
            valueColor: booking.isPaid
                ? CupertinoColors.systemGreen.resolveFrom(context)
                : CupertinoColors.systemRed.resolveFrom(context),
          ),
          if (booking.isPaid) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(CupertinoIcons.checkmark_circle,
                    size: 16,
                    color: CupertinoColors.systemGreen.resolveFrom(context)),
                const SizedBox(width: 4),
                Text(
                  'Paid in full',
                  style: TextStyle(
                    color: CupertinoColors.systemGreen.resolveFrom(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _InlineContactRow extends StatelessWidget {
  const _InlineContactRow({required this.contact});
  final BookingContact contact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: CupertinoColors.systemBlue
                  .resolveFrom(context)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                contact.name.isNotEmpty
                    ? contact.name[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                if (contact.role != null && contact.role!.isNotEmpty)
                  Text(contact.role!,
                      style: TextStyle(
                          fontSize: 13,
                          color: context.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
