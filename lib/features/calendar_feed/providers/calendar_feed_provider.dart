import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/calendar_feed_repository.dart';
import '../data/models/calendar_feed.dart';

// ── Repository provider ───────────────────────────────────────────────────────

final calendarFeedRepositoryProvider =
    Provider<CalendarFeedRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return CalendarFeedRepository(dio);
});

// ── Feed provider ─────────────────────────────────────────────────────────────

/// Fetches the user's calendar subscription URLs. Mints the token on first
/// access. Invalidate this provider after a reset to pull the rotated URLs.
final calendarFeedProvider = FutureProvider<CalendarFeed>((ref) async {
  return ref.watch(calendarFeedRepositoryProvider).getCalendarFeed();
});
