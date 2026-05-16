import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../../../auth/data/models/band_summary.dart';
import '../../../events/data/models/event_summary.dart';
import '../../data/models/booking_detail.dart';
import '../../data/models/deposit.dart';

class ContractFixedHeader extends StatelessWidget {
  const ContractFixedHeader({
    super.key,
    required this.booking,
    required this.band,
  });

  final BookingDetail booking;
  final BandSummary band;

  static final DateFormat _eventDateFmt = DateFormat('EEE M/d/yyyy');
  static final DateFormat _shortDateFmt = DateFormat('M/d/yyyy');
  static final DateFormat _timeFmt = DateFormat('h:mm a');

  String _formatTime(String? time) {
    if (time == null || time.isEmpty) return '';
    final parts = time.split(':');
    if (parts.length < 2) return time;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return time;
    return _timeFmt.format(DateTime(2000, 1, 1, h, m));
  }

  double _parsePrice() => double.tryParse(booking.price ?? '0') ?? 0;

  // TODO(mobile-contract-parity): once BookingDetail carries totalDuration,
  // read it here. Backend already emits the field (Task 1).
  double _parseDuration() => 4.0;

  int get _eventCount => booking.eventCount > 0 ? booking.eventCount : 1;

  static bool _isAbsoluteHttpUrl(String? s) {
    if (s == null || s.isEmpty) return false;
    final uri = Uri.tryParse(s);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  String get _overtimeRate {
    final price = _parsePrice();
    final duration = _parseDuration();
    if (duration <= 0 || _eventCount <= 0) return '0.00';
    return ((price / duration) * 1.5 / _eventCount).toStringAsFixed(2);
  }

  ResolvedDeposit get _resolvedDeposit => Deposit.resolve(booking);

  TextStyle _bold(BuildContext c) => CupertinoTheme.of(c)
      .textTheme
      .textStyle
      .copyWith(fontWeight: FontWeight.w700);

  Widget _bullet(BuildContext c, List<InlineSpan> spans) => Padding(
        padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
        child: Text.rich(
          TextSpan(children: [const TextSpan(text: '• '), ...spans]),
          style: CupertinoTheme.of(c).textTheme.textStyle,
        ),
      );

  List<EventSummary> _sortedEvents() {
    final list = [...booking.events];
    list.sort((a, b) {
      final cmp = a.date.compareTo(b.date);
      if (cmp != 0) return cmp;
      return (a.id ?? 0) - (b.id ?? 0);
    });
    return list;
  }

  String _eventLine(EventSummary ev) {
    final date = () {
      try {
        return _eventDateFmt.format(DateTime.parse(ev.date));
      } catch (_) {
        return ev.date;
      }
    }();
    final time = (ev.startTime != null && ev.endTime != null)
        ? ' (${_formatTime(ev.startTime)} – ${_formatTime(ev.endTime)})'
        : '';
    final venue = (ev.venueName != null && ev.venueName!.isNotEmpty)
        ? ' at ${ev.venueName}'
        : '';
    return '$date — ${ev.title}$venue$time';
  }

  @override
  Widget build(BuildContext context) {
    final firstContactName =
        booking.contacts.isNotEmpty ? booking.contacts.first.name : 'Buyer';

    final formattedStart = () {
      try {
        return _shortDateFmt.format(DateTime.parse(booking.startDate));
      } catch (_) {
        return 'TBD';
      }
    }();

    final style = CupertinoTheme.of(context).textTheme.textStyle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isAbsoluteHttpUrl(band.logo))
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 200, maxHeight: 100),
                child: Image.network(
                  band.logo!,
                  // Broken/unreachable logo shouldn't crash the contract
                  // screen — render nothing so the contract still renders.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(text: band.name, style: _bold(context)),
                const TextSpan(
                    text:
                        ' (hereinafter referred to as "Artist"), enter into this Agreement with '),
                TextSpan(text: firstContactName, style: _bold(context)),
                const TextSpan(
                    text:
                        ' (hereinafter referred to as "Buyer"), for the engagement of a live musical performance (hereinafter referred to as the "Venue"), subject to the following conditions:'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Details of engagement:', style: _bold(context)),
          const SizedBox(height: 6),
          if (booking.isMultiEvent) ...[
            _bullet(context, [
              TextSpan(text: 'Performances:', style: _bold(context)),
            ]),
            for (final ev in _sortedEvents())
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text('• ${_eventLine(ev)}', style: style),
              ),
            _bullet(context, [
              TextSpan(text: 'Total Performance Length: ', style: _bold(context)),
              TextSpan(text: '${_parseDuration()} hours'),
            ]),
            _bullet(context, [
              TextSpan(text: 'Sound Check Time: ', style: _bold(context)),
              const TextSpan(text: 'at least 1 hour before each performance'),
            ]),
          ] else ...[
            _bullet(context, [
              TextSpan(text: 'Date: ', style: _bold(context)),
              TextSpan(text: formattedStart),
            ]),
            _bullet(context, [
              TextSpan(text: 'Performance Length: ', style: _bold(context)),
              TextSpan(text: '${_parseDuration()} hours'),
            ]),
            _bullet(context, [
              TextSpan(text: 'Sound Check Time: ', style: _bold(context)),
              const TextSpan(text: 'at least 1 hour before performance'),
            ]),
            _bullet(context, [
              TextSpan(text: 'Venue: ', style: _bold(context)),
              TextSpan(text: booking.venueSummary ?? 'TBD'),
            ]),
          ],
          _bullet(context, [
            TextSpan(text: 'Point(s) of Contact:', style: _bold(context)),
          ]),
          for (final c in booking.contacts)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(
                '• ${c.name}'
                '${c.email != null ? " - ${c.email}" : ""}'
                '${c.phone != null ? " - ${c.phone}" : ""}',
                style: style,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'COMPENSATION AND DEPOSIT',
            style: _bold(context).copyWith(
              decoration: TextDecoration.underline,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: style,
              children: [
                const TextSpan(text: 'Buyer will pay a total of '),
                TextSpan(text: '\$${booking.price ?? "0"}', style: _bold(context)),
                const TextSpan(
                    text:
                        " to Artist as compensation for Artist's performance."),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: style,
              children: [
                const TextSpan(text: 'Buyer will pay a deposit of '),
                TextSpan(text: '\$${_resolvedDeposit.depositAmount}', style: _bold(context)),
                const TextSpan(
                    text:
                        ', within three weeks of the execution of this Agreement. The deposit is non-refundable after execution of this contract. Payment to '),
                TextSpan(text: band.name, style: _bold(context)),
                if (band.address != null) const TextSpan(text: '. Mailing address:'),
              ],
            ),
          ),
          if (band.address != null && band.address!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(band.name),
                  Text(band.address!),
                  Text('${band.city ?? ""}, ${band.state ?? ""} ${band.zip ?? ""}'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: style,
              children: [
                const TextSpan(text: 'Buyer shall pay the remaining gross compensation of '),
                TextSpan(text: '\$${_resolvedDeposit.remainingAmount}', style: _bold(context)),
                const TextSpan(
                    text: ' at least ten (10) days before Performance. Overtime rate: '),
                TextSpan(text: '\$$_overtimeRate/hour', style: _bold(context)),
                const TextSpan(text: ' (one additional hour max).'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
