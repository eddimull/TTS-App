import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/shared/utils/time_format.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/models/booking_contact.dart';
import '../data/models/booking_detail.dart';
import '../providers/bookings_provider.dart';

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
          message: 'Could not load booking.\n$e',
          onRetry: () => ref.invalidate(bookingDetailProvider(args)),
        ),
      ),
      data: (booking) => _BookingDetailView(booking: booking),
    );
  }
}

class _BookingDetailView extends StatelessWidget {
  const _BookingDetailView({required this.booking});

  final BookingDetail booking;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(booking.name),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoRow(
            icon: CupertinoIcons.calendar,
            label: 'Date',
            value: _formatDateAndTime(
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
            ),
          ],
          if (booking.status != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: CupertinoIcons.info_circle,
              label: 'Status',
              value: '',
              trailing: _StatusChip(status: booking.status!),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Financials',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _FinanceRow(
                  label: 'Total',
                  value: booking.displayPrice,
                  bold: true,
                ),
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
                          size: 16, color: CupertinoColors.systemGreen.resolveFrom(context)),
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
          ),
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Notes',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(booking.notes!,
                  style: const TextStyle(fontSize: 15)),
            ),
          ],
          if (booking.contacts.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Contacts',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...booking.contacts.map((c) => _ContactRow(contact: c)),
          ],
          if (booking.events.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Linked Events',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...booking.events.map((e) => _EventRow(event: e)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _formatDateAndTime(
      String date, String? startTime, String? endTime) {
    try {
      final dt = DateTime.parse(date);
      final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(dt);
      if (startTime != null && startTime.isNotEmpty) {
        if (endTime != null && endTime.isNotEmpty) {
          return '$dateStr, ${_toAmPm(startTime)} – ${_toAmPm(endTime)}';
        }
        return '$dateStr at ${_toAmPm(startTime)}';
      }
      return dateStr;
    } catch (_) {
      return startTime != null ? '$date at ${_toAmPm(startTime)}' : date;
    }
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
        Icon(icon, size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context))),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status.toLowerCase()) {
      'confirmed' => (
          'Confirmed',
          CupertinoColors.systemGreen.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemGreen.resolveFrom(context),
        ),
      'pending' => (
          'Pending',
          CupertinoColors.systemOrange.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemOrange.resolveFrom(context),
        ),
      'cancelled' || 'canceled' => (
          'Cancelled',
          CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.15),
          CupertinoColors.systemRed.resolveFrom(context),
        ),
      _ => (
          status,
          CupertinoColors.systemGrey5.resolveFrom(context),
          CupertinoColors.systemGrey.resolveFrom(context),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});

  final BookingContact contact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                contact.name.isNotEmpty
                    ? contact.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold),
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
                          color: CupertinoColors.secondaryLabel.resolveFrom(context))),
                if (contact.email != null && contact.email!.isNotEmpty)
                  Text(contact.email!,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context))),
                if (contact.phone != null && contact.phone!.isNotEmpty)
                  Text(contact.phone!,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context))),
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
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(CupertinoIcons.calendar,
                size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
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
                        color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 16, color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
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
