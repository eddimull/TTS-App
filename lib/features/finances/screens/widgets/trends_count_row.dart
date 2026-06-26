import 'package:flutter/cupertino.dart';
import '../../data/models/finance_trends.dart';

/// A per-month booking-count strip shown directly under the chart, so a low
/// dollar month visibly correlates with few bookings.
class TrendsCountRow extends StatelessWidget {
  const TrendsCountRow({super.key, required this.trends});

  final FinanceTrends trends;

  @override
  Widget build(BuildContext context) {
    final orange = CupertinoColors.systemOrange.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Padding(
      // Match the chart's horizontal inset; the left pad approximates the
      // chart's reserved y-axis width so counts sit under their bars.
      padding: const EdgeInsets.fromLTRB(64, 6, 28, 0),
      child: Row(
        children: [
          for (final m in trends.months)
            Expanded(
              child: Center(
                child: Text(
                  '${m.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: m.count > 0 ? FontWeight.w700 : FontWeight.w400,
                    color: m.count > 0 ? orange : secondaryLabel,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
