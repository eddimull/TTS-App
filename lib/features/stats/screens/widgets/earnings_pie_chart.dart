import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Doughnut chart — each band contributes an earned slice (band color) and,
/// when it has booked-but-unplayed gigs, a lighter "upcoming" slice in the
/// same hue. Legend lists each portion separately.
class EarningsPieChart extends StatelessWidget {
  const EarningsPieChart({super.key, required this.byBand});

  final List<BandBreakdown> byBand;

  // Fixed palette — cycles if there are more than 6 bands.
  static const _palette = [
    Color(0xFF34C759), // systemGreen
    Color(0xFF007AFF), // systemBlue
    Color(0xFFFF9500), // systemOrange
    Color(0xFFAF52DE), // systemPurple
    Color(0xFFFF3B30), // systemRed
    Color(0xFF5AC8FA), // systemTeal
  ];

  Color _colorFor(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    // Build (label, value, color) entries: earned then upcoming per band.
    final entries = <({String label, double value, Color color})>[];
    for (var i = 0; i < byBand.length; i++) {
      final band = byBand[i];
      final base = _colorFor(i);
      if (band.earned > 0) {
        entries.add((label: band.bandName, value: band.earned, color: base));
      }
      if (band.upcoming > 0) {
        entries.add((
          label: '${band.bandName} (upcoming)',
          value: band.upcoming,
          color: base.withValues(alpha: 0.4),
        ));
      }
    }

    final sections = entries
        .map((e) => PieChartSectionData(
              value: e.value,
              color: e.color,
              showTitle: false,
              radius: 60,
            ))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e.label,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        currency.format(e.value),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.primaryText,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
