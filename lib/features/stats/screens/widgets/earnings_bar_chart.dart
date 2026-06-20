import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';

/// Vertical stacked bar chart — one bar per year: earned (green) with the
/// upcoming (booked-but-unplayed) portion stacked on top in gray.
class EarningsBarChart extends StatelessWidget {
  const EarningsBarChart({super.key, required this.byYear});

  final List<YearBreakdown> byYear;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final gray = CupertinoColors.systemGrey.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    final maxY = byYear.map((e) => e.total).fold(0.0, (a, b) => a > b ? a : b);
    final chartMax = maxY * 1.1;

    final barGroups = byYear.asMap().entries.map((entry) {
      final y = entry.value;
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: y.total,
            // The stack items below cover the full 0→total range; set the base
            // rod transparent so fl_chart's default rod color can never show
            // through (e.g. on future-only years where earned == 0).
            color: const Color(0x00000000),
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            rodStackItems: [
              BarChartRodStackItem(0, y.earned, green),
              BarChartRodStackItem(y.earned, y.total, gray.withValues(alpha: 0.55)),
            ],
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
                    if (idx < 0 || idx >= byYear.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${byYear[idx].year}',
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
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, __) {
                  final y = byYear[group.x.toInt()];
                  final upcomingLine =
                      y.upcoming > 0 ? '\n${currency.format(y.upcoming)} upcoming' : '';
                  return BarTooltipItem(
                    '${y.year}\n${currency.format(y.earned)} earned$upcomingLine',
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
