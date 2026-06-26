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
    final current = trends.comparing ? trends.currentMonths : null;
    double dollars(int cents) => cents / 100.0;

    // Axis max spans both the snapshot and (when comparing) the current series.
    double maxY = 0;
    void consider(List<TrendMonth> ms) {
      for (final m in ms) {
        final stack = dollars(m.paidCents + m.unpaidCents);
        final f = dollars(m.forecastCents);
        maxY = [maxY, stack, f].reduce((a, b) => a > b ? a : b);
      }
    }

    consider(months);
    if (current != null) consider(current);
    final double chartMax = maxY > 0 ? maxY * 1.1 : 100;

    BarChartRodData stackedRod(
      TrendMonth m, {
      required double width,
      required double alpha,
    }) =>
        BarChartRodData(
          toY: dollars(m.paidCents + m.unpaidCents),
          width: width,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          color: const Color(0x00000000),
          rodStackItems: [
            BarChartRodStackItem(0, dollars(m.paidCents), blue.withValues(alpha: alpha)),
            BarChartRodStackItem(
              dollars(m.paidCents),
              dollars(m.paidCents + m.unpaidCents),
              gray.withValues(alpha: 0.55 * alpha),
            ),
          ],
        );

    final barGroups = months.asMap().entries.map((e) {
      final i = e.key;
      final m = e.value;
      return BarChartGroupData(
        x: i,
        // When comparing, a wide faded "current" rod sits behind a narrower
        // solid "snapshot" rod, so the chart shows then (solid) vs now (faded).
        barsSpace: 0,
        barRods: [
          if (current != null && i < current.length)
            stackedRod(current[i], width: 16, alpha: 0.30),
          stackedRod(m, width: current != null ? 9 : 11, alpha: 1.0),
        ],
        groupVertically: false,
        showingTooltipIndicators: const [],
      );
    }).toList();

    LineChartBarData line(
      List<TrendMonth> ms,
      Color color,
      double Function(TrendMonth) sel, {
      double alpha = 1.0,
    }) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < ms.length; i++) FlSpot(i.toDouble(), sel(ms[i])),
          ],
          isCurved: false,
          color: color.withValues(alpha: alpha),
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
                      if (current != null) ...[
                        line(current, green, (m) => dollars(m.forecastCents),
                            alpha: 0.3),
                        line(current, purple, (m) => dollars(m.netCents),
                            alpha: 0.3),
                      ],
                      line(months, green, (m) => dollars(m.forecastCents)),
                      line(months, purple, (m) => dollars(m.netCents)),
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
