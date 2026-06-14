/// Minutes of warning before the user must depart.
const Duration kDepartureWarning = Duration(minutes: 15);

/// The moment the user must leave to reach the first timeline item on time:
/// the item's time minus live travel duration.
DateTime departureTime({required DateTime firstItem, required Duration travel}) =>
    firstItem.subtract(travel);

/// When to fire the "leave in 15 minutes" reminder: [kDepartureWarning] before
/// the departure moment.
DateTime remindAt(DateTime departure) => departure.subtract(kDepartureWarning);

/// Within this distance of the venue the user has effectively arrived.
const double kArrivalRadiusMeters = 400;

/// Whether the departure reminder should be suppressed because the user has
/// already left or arrived.
///
/// - [travelToVenue]: live driving duration from current location.
/// - [timeUntilFirstItem]: time from now until the first timeline item.
/// - [metersToVenue]: straight-line distance from current location to venue.
/// - [pastDeparture]: whether now is at/after the computed departure moment.
bool hasAlreadyLeft({
  required Duration travelToVenue,
  required Duration timeUntilFirstItem,
  required double metersToVenue,
  required bool pastDeparture,
}) {
  if (metersToVenue <= kArrivalRadiusMeters) return true;
  if (pastDeparture && travelToVenue <= timeUntilFirstItem) return true;
  return false;
}
