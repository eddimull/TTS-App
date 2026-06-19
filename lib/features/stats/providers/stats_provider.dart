import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/stats_repository.dart';
import '../data/models/user_stats.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return StatsRepository(dio);
});

// ── Stats provider ────────────────────────────────────────────────────────────

/// Fetches the user's personal stats. Invalidate to refresh.
final userStatsProvider = FutureProvider<UserStats>((ref) async {
  return ref.watch(statsRepositoryProvider).getStats();
});
