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

// ── Feed notifier ─────────────────────────────────────────────────────────────

class CalendarFeedNotifier extends AsyncNotifier<CalendarFeed> {
  CalendarFeedRepository get _repo => ref.read(calendarFeedRepositoryProvider);

  /// Fetches the user's calendar subscription URLs, minting the token on first
  /// access.
  @override
  Future<CalendarFeed> build() => _repo.getCalendarFeed();

  /// Rotate the token, revoking the previously shared link. The reset endpoint
  /// already returns the rotated URLs, so we adopt them directly rather than
  /// triggering a second GET.
  Future<void> reset() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repo.resetCalendarFeed);
  }
}

final calendarFeedProvider =
    AsyncNotifierProvider<CalendarFeedNotifier, CalendarFeed>(
  CalendarFeedNotifier.new,
);
