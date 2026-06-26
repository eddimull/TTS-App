import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/band_revenue.dart';

/// Vertical bar chart — one bar per year of recorded revenue (chronological,
/// oldest on the left). Mirrors the style of the stats EarningsBarChart.
class RevenueBarChart extends StatelessWidget {
  const RevenueBarChart({super.key, required this.revenue});

  final BandRevenue revenue;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final blue = CupertinoColors.systemBlue.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    // API gives newest-first; chart reads left→right chronologically.
    final chrono = revenue.years.reversed.toList();

    final maxY = chrono
        .map((e) => e.totalDollars)
        .fold(0.0, (a, b) => a > b ? a : b);
    final chartMax = maxY * 1.1;

    final barGroups = chrono.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.totalDollars,
            color: blue,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 220,
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: BarChart(
          BarChartData(
            maxY: chartMax > 0 ? chartMax : 100,
            barGroups: barGroups,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: CupertinoColors.separator.resolveFrom(context),
                strokeWidth: 0.5,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, _) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= chrono.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${chrono[idx].year}',
                          style: TextStyle(fontSize: 11, color: secondaryLabel)),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, _) => Text(currency.format(value),
                      style: TextStyle(fontSize: 10, color: secondaryLabel)),
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) {
                  final y = chrono[group.x.toInt()];
                  return BarTooltipItem(
                    '${y.year}\n${currency.format(y.totalDollars)}',
                    const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
