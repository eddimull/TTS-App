import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';

/// Doughnut (pie with center space) chart — one slice per band.
/// Shows a legend with band names and amounts below the chart.
class EarningsPieChart extends StatelessWidget {
  const EarningsPieChart({super.key, required this.byBand});

  final List<BandEarnings> byBand;

  // Fixed palette — cycles if there are more than 6 bands.
  static const _palette = [
    Color(0xFF34C759), // systemGreen
    Color(0xFF007AFF), // activeBlue
    Color(0xFFFF9500), // systemOrange
    Color(0xFFAF52DE), // systemPurple
    Color(0xFFFF3B30), // systemRed
    Color(0xFF5AC8FA), // systemTeal
  ];

  Color _colorFor(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final sections = byBand.asMap().entries.map((entry) {
      final band = entry.value;
      return PieChartSectionData(
        value: band.total,
        color: _colorFor(entry.key),
        // Hide built-in labels — legend below handles labeling.
        showTitle: false,
        radius: 60,
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  // Doughnut: leave a center hole.
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Legend rows.
            ...byBand.asMap().entries.map((entry) {
              final band = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _colorFor(entry.key),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        band.bandName,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      currency.format(band.total),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
