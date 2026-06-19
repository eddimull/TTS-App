import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';

/// Vertical bar chart — one bar per year, value = total earnings.
class EarningsBarChart extends StatelessWidget {
  const EarningsBarChart({super.key, required this.byYear});

  final List<YearEarnings> byYear;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final secondaryLabel =
        CupertinoColors.secondaryLabel.resolveFrom(context);

    final maxY = byYear
        .map((e) => e.total)
        .fold(0.0, (a, b) => a > b ? a : b);
    // Give the chart 10% headroom above the tallest bar.
    final chartMax = maxY * 1.1;

    final barGroups = byYear.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.total,
            color: green,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 200,
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        decoration: BoxDecoration(
          color:
              CupertinoColors.tertiarySystemBackground.resolveFrom(context),
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
                    if (idx < 0 || idx >= byYear.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${byYear[idx].year}',
                        style: TextStyle(
                          fontSize: 11,
                          color: secondaryLabel,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, _) => Text(
                    currency.format(value),
                    style: TextStyle(fontSize: 10, color: secondaryLabel),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            // Tooltip shows the year and currency amount.
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) {
                  final idx = group.x.toInt();
                  final year = byYear[idx].year;
                  return BarTooltipItem(
                    '$year\n${currency.format(rod.toY)}',
                    const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.white,
                    ),
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
