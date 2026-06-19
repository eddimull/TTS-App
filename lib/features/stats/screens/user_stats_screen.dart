import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/stats_provider.dart';
import '../data/models/user_stats.dart';
import 'widgets/stats_summary_cards.dart';
import 'widgets/earnings_bar_chart.dart';
import 'widgets/earnings_pie_chart.dart';
import 'widgets/bookings_by_year_section.dart';
import 'widgets/mileage_by_year_section.dart';
import 'widgets/performance_map.dart';
import 'widgets/recent_locations_list.dart';
import 'widgets/stats_section_header.dart';

/// Personal stats screen — mirrors the web /stats page.
/// Mounted from More > My Stats via GoRouter (/stats).
class UserStatsScreen extends ConsumerWidget {
  const UserStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('My Stats'),
      ),
      child: SafeArea(
        child: statsAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, __) => _ErrorState(
            onRetry: () => ref.invalidate(userStatsProvider),
          ),
          data: (stats) => stats.isEmpty
              ? const _EmptyState()
              : _StatsContent(stats: stats),
        ),
      ),
    );
  }
}

// ── Content ───────────────────────────────────────────────────────────────────

class _StatsContent extends StatelessWidget {
  const _StatsContent({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final geoLocations = stats.locations
        .where((l) => l.hasCoordinates)
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        // Context note — mirrors the web page: stats are personal and based on
        // each band's payout config, counting only bookings after you joined.
        const _InfoBanner(),
        const SizedBox(height: 16),

        // 1. Summary cards — Earnings / Distance / Events
        StatsSummaryCards(stats: stats),
        const SizedBox(height: 24),

        // 2. Earnings by Year bar chart
        if (stats.payments.yearBreakdown.isNotEmpty) ...[
          const StatsSectionHeader(title: 'Earnings by Year'),
          const SizedBox(height: 8),
          EarningsBarChart(byYear: stats.payments.yearBreakdown),
          const SizedBox(height: 24),
        ],

        // 3. Earnings by Band doughnut chart
        if (stats.payments.bandBreakdown.isNotEmpty) ...[
          const StatsSectionHeader(title: 'Earnings by Band'),
          const SizedBox(height: 8),
          EarningsPieChart(byBand: stats.payments.bandBreakdown),
          const SizedBox(height: 24),
        ],

        // 4. Bookings by Year — expandable
        if (stats.payments.bookingsByYear.isNotEmpty) ...[
          const StatsSectionHeader(title: 'Bookings by Year'),
          const SizedBox(height: 4),
          BookingsByYearSection(bookingsByYear: stats.payments.bookingsByYear),
          const SizedBox(height: 24),
        ],

        // 5. Mileage by Year — expandable
        if (stats.travel.byYear.isNotEmpty) ...[
          const StatsSectionHeader(title: 'Mileage by Year'),
          const SizedBox(height: 4),
          MileageByYearSection(travelByYear: stats.travel.byYear),
          const SizedBox(height: 24),
        ],

        // 6. Performance map — only when we have geocoded locations
        if (geoLocations.isNotEmpty) ...[
          const StatsSectionHeader(title: 'Where I\'ve Performed'),
          const SizedBox(height: 8),
          PerformanceMap(locations: geoLocations),
          const SizedBox(height: 24),
        ],

        // 7. Recent locations list (first ~20)
        if (stats.locations.isNotEmpty) ...[
          const StatsSectionHeader(title: 'Recent Locations'),
          const SizedBox(height: 4),
          RecentLocationsList(
            locations: stats.locations.take(20).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

// ── Info banner ───────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBlue
              .resolveFrom(context)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              CupertinoIcons.info_circle_fill,
              size: 18,
              color: CupertinoColors.systemBlue.resolveFrom(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your personal earnings, based on each band’s payment setup. '
                'Only bookings from after you joined each band are counted.',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 44,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your stats.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 16),
            CupertinoButton.filled(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.chart_bar_alt_fill,
              size: 56,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No stats yet',
              style: CupertinoTheme.of(context)
                  .textTheme
                  .navLargeTitleTextStyle
                  .copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Your earnings and travel stats will appear here once you have completed bookings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
