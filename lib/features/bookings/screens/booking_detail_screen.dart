import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import 'package:tts_bandmate/shared/widgets/status_chip.dart';
import '../data/bookings_repository.dart';
import '../data/models/booking_contact.dart';
import '../data/models/booking_detail.dart';
import '../providers/bookings_provider.dart';
import '../widgets/booking_section_tile.dart';

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
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
            'Are you sure you want to cancel this booking? This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
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
      ref.invalidate(
          bookingDetailProvider((bandId: widget.bandId, bookingId: widget.bookingId)));
      ref.invalidate(bandBookingsProvider(
          BandBookingsParams(bandId: widget.bandId)));
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
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Booking'),
        content: const Text(
            'This will permanently delete the booking. Are you sure?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
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
      ref.invalidate(bandBookingsProvider(
          BandBookingsParams(bandId: widget.bandId)));
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
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Error'),
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

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
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
                // ── Info card ─────────────────────────────────────────────
                const SizedBox(height: 12),
                _InfoCard(booking: b),

                // ── Financial summary ─────────────────────────────────────
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _FinancialsCard(booking: b),
                ),

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

                // ── Linked events ─────────────────────────────────────────
                if (b.events.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _SectionHeader(label: 'Linked Events'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.tertiarySystemBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: b.events
                            .map((e) => _EventRow(event: e))
                            .toList(),
                      ),
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
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.booking});
  final BookingDetail booking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              icon: CupertinoIcons.calendar,
              label: 'Date',
              value: formatDateWithTimeRange(
                  booking.date, booking.startTime, booking.endTime),
            ),
            if (booking.venueName != null &&
                booking.venueName!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: CupertinoIcons.location,
                label: 'Venue',
                value: [
                  booking.venueName!,
                  if (booking.venueAddress != null &&
                      booking.venueAddress!.isNotEmpty)
                    booking.venueAddress!,
                ].join('\n'),
                trailing: booking.venueAddress != null &&
                        booking.venueAddress!.isNotEmpty
                    ? CupertinoButton(
                        padding: const EdgeInsets.only(top: 4),
                        onPressed: () async {
                          final uri = Uri.parse(
                              'https://maps.google.com/?q=${Uri.encodeComponent(booking.venueAddress!)}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.map_pin, size: 14),
                            SizedBox(width: 4),
                            Text('View in Maps',
                                style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      )
                    : null,
              ),
            ],
            if (booking.status != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: CupertinoIcons.info_circle,
                label: 'Status',
                value: '',
                trailing: StatusChip(status: booking.status!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 20,
            color: CupertinoColors.secondaryLabel.resolveFrom(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context))),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
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
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final BookingEvent event;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => GoRouter.of(context).push('/events/${event.key}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(CupertinoIcons.calendar,
                size: 20,
                color: CupertinoColors.secondaryLabel.resolveFrom(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  Text(
                    _formatDate(event.date, event.time),
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context)),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 16,
                color:
                    CupertinoColors.tertiaryLabel.resolveFrom(context)),
          ],
        ),
      ),
    );
  }

  String _formatDate(String date, String? time) {
    try {
      final dt = DateTime.parse(date);
      final dateStr = DateFormat('MMM d, yyyy').format(dt);
      if (time != null && time.isNotEmpty) return '$dateStr at $time';
      return dateStr;
    } catch (_) {
      return time != null ? '$date at $time' : date;
    }
  }
}
