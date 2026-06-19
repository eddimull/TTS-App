import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';

/// Expandable list of yearly travel summaries with per-event travel rows.
class MileageByYearSection extends StatefulWidget {
  const MileageByYearSection({super.key, required this.travelByYear});

  final List<TravelYear> travelByYear;

  @override
  State<MileageByYearSection> createState() => _MileageByYearSectionState();
}

class _MileageByYearSectionState extends State<MileageByYearSection> {
  late final Set<int> _expanded;

  @override
  void initState() {
    super.initState();
    // Default: most recent year (index 0) open.
    _expanded = widget.travelByYear.isNotEmpty ? {0} : {};
  }

  void _toggle(int index) {
    setState(() {
      if (_expanded.contains(index)) {
        _expanded.remove(index);
      } else {
        _expanded.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: widget.travelByYear.asMap().entries.map((entry) {
        return _TravelYearGroup(
          year: entry.value,
          isExpanded: _expanded.contains(entry.key),
          onToggle: () => _toggle(entry.key),
        );
      }).toList(),
    );
  }
}

// ── Year group header + collapsed/expanded body ───────────────────────────────

class _TravelYearGroup extends StatelessWidget {
  const _TravelYearGroup({
    required this.year,
    required this.isExpanded,
    required this.onToggle,
  });

  final TravelYear year;
  final bool isExpanded;
  final VoidCallback onToggle;

  String _formatMiles(double miles) {
    if (miles == miles.truncateToDouble()) return miles.truncate().toString();
    return miles.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
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
              label:
                  '${year.year}, ${year.eventCount} events, ${_formatMiles(year.totalMiles)} miles',
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
                              '${year.year}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${year.eventCount} event${year.eventCount == 1 ? '' : 's'}  •  ${_formatMiles(year.totalMiles)} mi',
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoColors.secondaryLabel
                                    .resolveFrom(context),
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
                        color:
                            CupertinoColors.tertiaryLabel.resolveFrom(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Expanded event rows.
            if (isExpanded) ...[
              Container(
                height: 0.5,
                color: CupertinoColors.separator.resolveFrom(context),
              ),
              ...year.events.asMap().entries.map((entry) {
                final isLast = entry.key == year.events.length - 1;
                return Column(
                  children: [
                    _TravelEventDetailRow(event: entry.value),
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

// ── Per-event travel detail row ───────────────────────────────────────────────

class _TravelEventDetailRow extends StatelessWidget {
  const _TravelEventDetailRow({required this.event});

  final TravelEventRow event;

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _fmt(double? value, String suffix) {
    if (value == null) return '—';
    if (value == value.truncateToDouble()) {
      return '${value.truncate()}$suffix';
    }
    return '${value.toStringAsFixed(1)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          Text(
            _formatDate(event.date),
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 3),
          // Event title + band
          Text(
            event.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (event.bandName.isNotEmpty)
            Text(
              event.bandName,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          // Venue
          Text(
            event.venueAddress != null && event.venueAddress!.isNotEmpty
                ? '${event.venueName}  •  ${event.venueAddress}'
                : event.venueName,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 4),
          // Distance + time
          Row(
            children: [
              Text(
                _fmt(event.miles, ' mi'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 12),
              Text(
                _fmt(event.hours, ' hrs'),
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
