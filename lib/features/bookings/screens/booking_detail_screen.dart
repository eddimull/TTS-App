import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorView(
          message: 'Could not load booking.\n$e',
          onRetry: () => ref.invalidate(bookingDetailProvider(args)),
        ),
      ),
      data: (booking) => _BookingDetailView(booking: booking),
    );
  }
}

// ── Detail view ───────────────────────────────────────────────────────────────

class _BookingDetailView extends StatelessWidget {
  const _BookingDetailView({required this.booking});

  final BookingDetail booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(booking.name),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date + time.
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: _formatDateAndTime(
                booking.date, booking.startTime, booking.endTime),
          ),
          // Venue.
          if (booking.venueName != null &&
              booking.venueName!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Venue',
              value: [
                booking.venueName!,
                if (booking.venueAddress != null &&
                    booking.venueAddress!.isNotEmpty)
                  booking.venueAddress!,
              ].join('\n'),
            ),
          ],
          // Status.
          if (booking.status != null) ...[
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.info_outline,
              label: 'Status',
              value: '',
              trailing: _StatusChip(status: booking.status!),
            ),
          ],
          // Price section.
          const SizedBox(height: 20),
          Text(
            'Financials',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
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
                  valueColor: Colors.green.shade700,
                ),
                const SizedBox(height: 6),
                _FinanceRow(
                  label: 'Balance due',
                  value: booking.displayAmountDue,
                  valueColor: booking.isPaid
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
                if (booking.isPaid) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Paid in full',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Notes.
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Notes',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                booking.notes!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          // Contacts section.
          if (booking.contacts.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Contacts',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...booking.contacts.map(
              (contact) => _ContactRow(contact: contact),
            ),
          ],
          // Events section.
          if (booking.events.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Linked Events',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...booking.events.map(
              (event) => _EventRow(event: event),
            ),
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
          return '$dateStr, $startTime – $endTime';
        }
        return '$dateStr at $startTime';
      }
      return dateStr;
    } catch (_) {
      return startTime != null ? '$date at $startTime' : date;
    }
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

// ── Finance row ───────────────────────────────────────────────────────────────

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
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status.toLowerCase()) {
      'confirmed' => (
          'Confirmed',
          Colors.green.shade100,
          Colors.green.shade800,
        ),
      'pending' => (
          'Pending',
          Colors.amber.shade100,
          Colors.amber.shade800,
        ),
      'cancelled' || 'canceled' => (
          'Cancelled',
          Colors.red.shade100,
          Colors.red.shade800,
        ),
      _ => (
          status,
          Colors.grey.shade200,
          Colors.grey.shade700,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Contact row ───────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});

  final BookingContact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Text(
              contact.name.isNotEmpty
                  ? contact.name[0].toUpperCase()
                  : '?',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (contact.role != null && contact.role!.isNotEmpty)
                  Text(
                    contact.role!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (contact.email != null && contact.email!.isNotEmpty)
                  Text(
                    contact.email!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (contact.phone != null && contact.phone!.isNotEmpty)
                  Text(
                    contact.phone!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event row ─────────────────────────────────────────────────────────────────

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final BookingEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.event_outlined,
        color: colorScheme.onSurfaceVariant,
      ),
      title: Text(
        event.title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        _formatDate(event.date, event.time),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: () => GoRouter.of(context).push('/events/${event.key}'),
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
