import '../../../core/network/geocoding.dart';
import '../data/leave_by.dart';

/// Minimal scheduling surface the enrichment logic needs (implemented by
/// PushService). Keeps the decision logic testable without plugins.
abstract class LocalScheduler {
  Future<void> scheduleLocal({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  });
  Future<void> cancelLocal(int id);
}

/// All inputs the pure enrichment decision needs. `now`, `origin`, `travel`,
/// and `metersToVenue` are gathered by the caller (clock + location + routes).
class EnrichmentInput {
  const EnrichmentInput({
    required this.notificationId,
    required this.eventTitle,
    required this.venue,
    required this.firstItemTitle,
    required this.firstItem,
    required this.now,
    required this.origin,
    required this.travel,
    required this.metersToVenue,
  });

  final int notificationId;
  final String eventTitle;
  final String? venue;
  final String firstItemTitle;
  final DateTime firstItem;
  final DateTime now;
  final GeoPoint origin;
  final Duration travel;
  final double metersToVenue;
}

/// Decide and act: schedule the precise departure reminder, suppress it (cancel
/// any existing), or skip when it's already too late. Pure decision over the
/// injected inputs; side effects go through [scheduler].
Future<void> enrich(EnrichmentInput input, LocalScheduler scheduler) async {
  final departure = departureTime(firstItem: input.firstItem, travel: input.travel);
  final remind = remindAt(departure);
  final timeUntilFirstItem = input.firstItem.difference(input.now);
  final pastDeparture = !input.now.isBefore(departure);

  if (hasAlreadyLeft(
    travelToVenue: input.travel,
    timeUntilFirstItem: timeUntilFirstItem,
    metersToVenue: input.metersToVenue,
    pastDeparture: pastDeparture,
  )) {
    await scheduler.cancelLocal(input.notificationId);
    return;
  }

  if (!remind.isAfter(input.now)) {
    // Too late to be useful; leave the server's time-based push as the floor.
    return;
  }

  await scheduler.scheduleLocal(
    id: input.notificationId,
    title: input.eventTitle,
    body: buildLeaveByBody(
      venue: input.venue,
      firstItemTitle: input.firstItemTitle,
      departure: departure,
    ),
    when: remind,
  );
}
