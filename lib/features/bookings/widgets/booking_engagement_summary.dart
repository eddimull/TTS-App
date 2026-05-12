import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../data/models/booking_detail.dart';

/// Top-of-screen engagement summary: optional `[N events]` chip on
/// multi-event bookings, and a one-line subtitle
/// "$count event(s) · $dateRange · $venueSummary".
class BookingEngagementSummary extends StatelessWidget {
  const BookingEngagementSummary({super.key, required this.booking});

  final BookingDetail booking;

  @override
  Widget build(BuildContext context) {
    final count = booking.eventCount;
    final dateRange = _formatDateRange(booking);
    final venue = booking.venueSummary;
    final parts = <String>[
      '$count ${count == 1 ? 'event' : 'events'}',
      dateRange,
    ];
    if (venue != null && venue.isNotEmpty) parts.add(venue);
    final subtitle = parts.join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (booking.isMultiEvent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: CupertinoColors.activeBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${booking.eventCount} events',
                style: const TextStyle(
                  color: CupertinoColors.activeBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateRange(BookingDetail booking) {
    try {
      final start = DateTime.parse(booking.startDate);
      final end = DateTime.parse(booking.endDate);
      final df = DateFormat('MMM d');
      if (start == end) return df.format(start);
      return '${df.format(start)} – ${df.format(end)}';
    } catch (_) {
      return booking.startDate;
    }
  }
}
