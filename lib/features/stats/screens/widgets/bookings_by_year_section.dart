import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Expandable list of yearly booking summaries with per-booking detail rows.
class BookingsByYearSection extends StatefulWidget {
  const BookingsByYearSection({super.key, required this.bookingsByYear});

  final List<BookingsYear> bookingsByYear;

  @override
  State<BookingsByYearSection> createState() => _BookingsByYearSectionState();
}

class _BookingsByYearSectionState extends State<BookingsByYearSection> {
  // Track which years are expanded, keyed by the year value (not list index) so
  // the state stays correct if the list order/length changes after a refresh.
  // A null key is the year-less "TBD" bucket (bookings with no gig date yet).
  // Lazily seeded with the most recent year the first time we build.
  final Set<int?> _expanded = {};
  bool _seededDefault = false;

  void _toggle(int? year) {
    setState(() {
      if (!_expanded.remove(year)) {
        _expanded.add(year);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_seededDefault && widget.bookingsByYear.isNotEmpty) {
      // Default-expand the most recent real year. Fall back to the first
      // element only if every group is the year-less "TBD" bucket, so an
      // undated bucket doesn't get expanded ahead of actual years.
      final firstReal = widget.bookingsByYear
          .firstWhere((y) => y.year != null, orElse: () => widget.bookingsByYear.first);
      _expanded.add(firstReal.year);
      _seededDefault = true;
    }

    return Column(
      children: widget.bookingsByYear.map((year) {
        return _YearGroup(
          year: year,
          isExpanded: _expanded.contains(year.year),
          onToggle: () => _toggle(year.year),
        );
      }).toList(),
    );
  }
}

// ── Year group header + collapsed/expanded body ───────────────────────────────

class _YearGroup extends StatelessWidget {
  const _YearGroup({
    required this.year,
    required this.isExpanded,
    required this.onToggle,
  });

  final BookingsYear year;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    // Bookings with no events yet have no year — bucket them under "TBD".
    final yearLabel = year.year?.toString() ?? 'TBD';
    final totalBookings = year.bookingCount + year.upcomingBookingCount;
    final hasUpcoming = year.upcomingBookingCount > 0;
    final bookingWord =
        '$totalBookings booking${totalBookings == 1 ? '' : 's'}';

    // Compact inline line: "43 bookings · $1,000 earned · $400 upcoming".
    final inlineLine = StringBuffer(
      '$bookingWord · ${currency.format(year.yearTotal)} earned',
    );
    if (hasUpcoming) {
      inlineLine.write(' · ${currency.format(year.upcomingTotal)} upcoming');
    }

    // Spoken form spells out the separators for screen readers.
    final spoken = StringBuffer(
      '$yearLabel, $bookingWord, ${currency.format(year.yearTotal)} earned',
    );
    if (hasUpcoming) {
      spoken.write(', ${currency.format(year.upcomingTotal)} upcoming');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color:
              CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Tappable header.
            Semantics(
              button: true,
              label: spoken.toString(),
              child: GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              yearLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              inlineLine.toString(),
                              style: TextStyle(
                                fontSize: 13,
                                color: context.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 14,
                        color: context.tertiaryText,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Expanded booking rows.
            if (isExpanded) ...[
              Container(
                height: 0.5,
                color: CupertinoColors.separator.resolveFrom(context),
              ),
              ...year.bookings.asMap().entries.map((entry) {
                final isLast = entry.key == year.bookings.length - 1;
                return Column(
                  children: [
                    _BookingDetailRow(booking: entry.value),
                    if (!isLast)
                      Container(
                        height: 0.5,
                        margin: const EdgeInsets.only(left: 14),
                        color: CupertinoColors.separator.resolveFrom(context),
                      ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Per-booking detail row ────────────────────────────────────────────────────

class _BookingDetailRow extends StatelessWidget {
  const _BookingDetailRow({required this.booking});

  final BookingRow booking;

  String _formatDate(String raw) {
    // Bookings with no events yet have an empty date (treated as upcoming);
    // show a placeholder for those. For a non-empty but unparseable string,
    // fall back to the raw value (consistent with the other stats date
    // formatters) rather than masking a real backend value as "TBD".
    if (raw.isEmpty) {
      return 'TBD';
    }
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final green = CupertinoColors.systemGreen.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date (+ an "Upcoming" badge for gigs that haven't happened yet)
          Row(
            children: [
              Text(
                _formatDate(booking.date),
                style: TextStyle(
                  fontSize: 12,
                  color: context.secondaryText,
                ),
              ),
              if (booking.isUpcoming) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemOrange
                        .resolveFrom(context)
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Upcoming',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color:
                          CupertinoColors.systemOrange.resolveFrom(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          // Booking name + band
          Text(
            booking.bookingName,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (booking.bandName.isNotEmpty)
            Text(
              booking.bandName,
              style: TextStyle(
                fontSize: 13,
                color: context.secondaryText,
              ),
            ),
          // Venue
          Text(
            booking.venueAddress != null && booking.venueAddress!.isNotEmpty
                ? '${booking.venueName}  •  ${booking.venueAddress}'
                : booking.venueName,
            style: TextStyle(
              fontSize: 12,
              color: context.tertiaryText,
            ),
          ),
          const SizedBox(height: 4),
          // Prices row
          Row(
            children: [
              Text(
                'Total: ${currency.format(booking.totalPrice)}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 12),
              // My share highlighted in green.
              const Text(
                'My share: ',
                style: TextStyle(fontSize: 13),
              ),
              Text(
                currency.format(booking.userShare),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
