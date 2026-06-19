import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../../data/models/user_stats.dart';


/// Three summary cards: Earnings | Distance | Events
class StatsSummaryCards extends StatelessWidget {
  const StatsSummaryCards({super.key, required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On narrow screens stack cards vertically; on wide screens use a row.
          if (constraints.maxWidth < 500) {
            return Column(
              children: [
                _SummaryCard(
                  icon: CupertinoIcons.money_dollar_circle_fill,
                  iconColor: CupertinoColors.systemGreen,
                  title: 'Total Earnings',
                  primary: currency.format(stats.payments.totalEarnings),
                  secondary:
                      '${stats.payments.bookingCount} booking${stats.payments.bookingCount == 1 ? '' : 's'}',
                ),
                const SizedBox(height: 10),
                _SummaryCard(
                  icon: CupertinoIcons.car_fill,
                  iconColor: CupertinoColors.activeBlue,
                  title: 'Distance Traveled',
                  primary:
                      '${_formatNumber(stats.travel.totalMiles)} mi',
                  secondary: '${_formatNumber(stats.travel.totalHours)} hrs',
                ),
                const SizedBox(height: 10),
                _SummaryCard(
                  icon: CupertinoIcons.music_mic,
                  iconColor: CupertinoColors.systemOrange,
                  title: 'Events Played',
                  primary: '${stats.travel.eventCount}',
                  secondary:
                      '${stats.locations.length} venue${stats.locations.length == 1 ? '' : 's'}',
                ),
              ],
            );
          }

          // Wide layout — row of three equal-width cards.
          return Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  icon: CupertinoIcons.money_dollar_circle_fill,
                  iconColor: CupertinoColors.systemGreen,
                  title: 'Total Earnings',
                  primary: currency.format(stats.payments.totalEarnings),
                  secondary:
                      '${stats.payments.bookingCount} booking${stats.payments.bookingCount == 1 ? '' : 's'}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryCard(
                  icon: CupertinoIcons.car_fill,
                  iconColor: CupertinoColors.activeBlue,
                  title: 'Distance Traveled',
                  primary:
                      '${_formatNumber(stats.travel.totalMiles)} mi',
                  secondary: '${_formatNumber(stats.travel.totalHours)} hrs',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryCard(
                  icon: CupertinoIcons.music_mic,
                  iconColor: CupertinoColors.systemOrange,
                  title: 'Events Played',
                  primary: '${stats.travel.eventCount}',
                  secondary:
                      '${stats.locations.length} venue${stats.locations.length == 1 ? '' : 's'}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Format a double to a concise string — drop trailing zeros where clean.
  String _formatNumber(double value) {
    if (value == value.truncateToDouble()) {
      return value.truncate().toString();
    }
    return value.toStringAsFixed(1);
  }
}

// ── Individual card ───────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.primary,
    required this.secondary,
  });

  final IconData icon;
  final CupertinoDynamicColor iconColor;
  final String title;
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    final resolvedIcon = iconColor.resolveFrom(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: resolvedIcon),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            primary,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            secondary,
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}
