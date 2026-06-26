import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/finance_trends.dart';

/// Per-month finance chart: paid + unpaid bars with forecast/net line overlays
/// on a single dollar axis. Tap a month for a tooltip with its figures.
class TrendsChart extends StatelessWidget {
  const TrendsChart({super.key, required this.trends});

  final FinanceTrends trends;

  static const _monthLabels = [
    'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
  ];

  // Left axis reserved width — shared by the bar chart and the line overlay so
  // the lines align with the bars.
  static const double _leftReserved = 48;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final blue = CupertinoColors.systemBlue.resolveFrom(context);
    final gray = CupertinoColors.systemGrey.resolveFrom(context);
    final green = CupertinoColors.systemGreen.resolveFrom(context);
    final purple = CupertinoColors.systemPurple.resolveFrom(context);
    final secondaryLabel = CupertinoColors.secondaryLabel.resolveFrom(context);

    final months = trends.months;
    double dollars(int cents) => cents / 100.0;

    double maxY = 0;
    for (final m in months) {
      final stack = dollars(m.paidCents + m.unpaidCents);
      final f = dollars(m.forecastCents);
      maxY = [maxY, stack, f].reduce((a, b) => a > b ? a : b);
    }
    final double chartMax = maxY > 0 ? maxY * 1.1 : 100;

    final barGroups = months.asMap().entries.map((e) {
      final m = e.value;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: dollars(m.paidCents + m.unpaidCents),
            width: 9,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            color: const Color(0x00000000),
            rodStackItems: [
              BarChartRodStackItem(0, dollars(m.paidCents), blue),
              BarChartRodStackItem(
                dollars(m.paidCents),
                dollars(m.paidCents + m.unpaidCents),
                gray.withValues(alpha: 0.55),
              ),
            ],
          ),
        ],
      );
    }).toList();

    LineChartBarData line(Color color, double Function(TrendMonth) sel) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < months.length; i++)
              FlSpot(i.toDouble(), sel(months[i])),
          ],
          isCurved: false,
          color: color,
          barWidth: 1.8,
          dotData: const FlDotData(show: false),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 220,
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            BarChart(
              BarChartData(
                maxY: chartMax,
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
                        if (idx < 0 || idx >= _monthLabels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_monthLabels[idx],
                              style:
                                  TextStyle(fontSize: 10, color: secondaryLabel)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _leftReserved,
                      getTitlesWidget: (value, _) => Text(currency.format(value),
                          style: TextStyle(fontSize: 9, color: secondaryLabel)),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, __) {
                      final m = months[group.x.toInt()];
                      final money =
                          NumberFormat.currency(symbol: '\$', decimalDigits: 0);
                      return BarTooltipItem(
                        '${DateFormat('MMMM').format(DateTime(trends.year, m.month))}\n'
                        '${m.count} ${m.count == 1 ? 'booking' : 'bookings'}\n'
                        '${money.format(dollars(m.paidCents))} paid\n'
                        '${money.format(dollars(m.unpaidCents))} unpaid\n'
                        '${money.format(dollars(m.forecastCents))} forecast\n'
                        '${money.format(dollars(m.netCents))} band cut',
                        const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Forecast + net lines drawn over the bars. The left padding matches
            // the bar chart's reserved y-axis width so the lines align; the
            // bottom padding matches the bar chart's x-axis label band.
            Padding(
              padding: const EdgeInsets.only(left: _leftReserved, bottom: 22),
              child: IgnorePointer(
                child: LineChart(
                  LineChartData(
                    minX: -0.5,
                    maxX: months.length - 0.5,
                    minY: 0,
                    maxY: chartMax,
                    lineBarsData: [
                      line(green, (m) => dollars(m.forecastCents)),
                      line(purple, (m) => dollars(m.netCents)),
                    ],
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
