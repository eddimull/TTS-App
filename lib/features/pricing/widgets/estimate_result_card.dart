import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import '../data/models/price_estimate.dart';

final _money = NumberFormat.currency(symbol: r'$', decimalDigits: 0);
final _moneyExact = NumberFormat.currency(symbol: r'$');

String formatMoney(double v) =>
    v == v.roundToDouble() ? _money.format(v) : _moneyExact.format(v);

/// Result of a price estimate: big number, range, confidence, breakdown,
/// warnings and comparables. Pure display; the caller supplies [onUsePrice]
/// when a "Use this price" action makes sense (booking form sheet).
class EstimateResultCard extends StatelessWidget {
  const EstimateResultCard({super.key, required this.estimate, this.onUsePrice});

  final PriceEstimate estimate;
  final VoidCallback? onUsePrice;

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (estimate.hasEstimate) ..._headline(context),
          if (!estimate.hasEstimate) _noEstimate(context),
          if (estimate.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final w in estimate.warnings) _WarningRow(warning: w),
          ],
          if (estimate.hasEstimate && estimate.breakdown.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(context, 'BREAKDOWN'),
            const SizedBox(height: 6),
            for (final line in estimate.breakdown) _BreakdownRow(line: line),
          ],
          if (estimate.comparables.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionTitle(context, 'COMPARABLE BOOKINGS'),
            const SizedBox(height: 6),
            for (final c in estimate.comparables) _ComparableRow(item: c),
          ],
          if (estimate.hasEstimate && onUsePrice != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: onUsePrice,
                child: const Text('Use this price'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _headline(BuildContext context) {
    final low = estimate.low;
    final high = estimate.high;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'SUGGESTED PRICE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.secondaryText,
              ),
            ),
          ),
          _ConfidenceBadge(confidence: estimate.confidence),
        ],
      ),
      const SizedBox(height: 4),
      Semantics(
        label: 'Suggested price ${formatMoney(estimate.estimate!)}',
        child: Text(
          formatMoney(estimate.estimate!),
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700),
        ),
      ),
      if (low != null && high != null)
        Text(
          'Range ${formatMoney(low)} – ${formatMoney(high)}',
          style: TextStyle(fontSize: 15, color: context.secondaryText),
        ),
      const SizedBox(height: 4),
      Text(
        _basisText(),
        style: TextStyle(fontSize: 13, color: context.tertiaryText),
      ),
    ];
  }

  String _basisText() {
    switch (estimate.baselineSource) {
      case 'manual':
        return 'Based on your manual base rate';
      case 'band_average':
        return 'Based on your average across all event types '
            '(${estimate.sampleSize} bookings)';
      case 'history':
        return 'Based on ${estimate.sampleSize} past bookings';
      default:
        return '';
    }
  }

  Widget _noEstimate(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Not enough booking history to suggest a price. Set a base rate for '
          'this event type in Pricing Rules.',
          style: TextStyle(fontSize: 15, color: context.secondaryText),
        ),
      );

  Widget _sectionTitle(BuildContext context, String t) => Text(
        t,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.secondaryText,
        ),
      );
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.confidence});
  final String confidence;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (confidence) {
      'high' => ('High confidence', CupertinoColors.systemGreen),
      'medium' => ('Medium confidence', CupertinoColors.systemOrange),
      _ => ('Low confidence', CupertinoColors.systemRed),
    };
    final resolved = color.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: resolved),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.line});
  final PriceBreakdownLine line;

  @override
  Widget build(BuildContext context) {
    final isBase = line.type == 'base';
    String amount;
    Color? color;
    if (isBase) {
      amount = formatMoney(line.amount);
    } else {
      final sign = line.amount > 0 ? '+' : (line.amount < 0 ? '−' : '');
      amount = '$sign${formatMoney(line.amount.abs())}';
      color = line.amount > 0
          ? CupertinoColors.systemGreen.resolveFrom(context)
          : line.amount < 0
              ? CupertinoColors.systemRed.resolveFrom(context)
              : context.secondaryText;
    }
    final factor = line.factor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              factor != null
                  ? '${line.label} (×${_trimFactor(factor)})'
                  : line.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBase ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amount,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBase ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _trimFactor(double f) {
    final s = f.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.warning});
  final PriceWarning warning;

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.systemOrange.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill,
              size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(warning.message, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _ComparableRow extends StatelessWidget {
  const _ComparableRow({required this.item});
  final PriceComparable item;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (item.date != null) item.date!,
      if (item.venueName != null && item.venueName!.isNotEmpty) item.venueName!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(fontSize: 14)),
                if (sub.isNotEmpty)
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12, color: context.secondaryText)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (item.price != null)
            Text(formatMoney(item.price!),
                style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
