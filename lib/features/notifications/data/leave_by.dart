/// Minutes of warning before the user must depart.
const Duration kDepartureWarning = Duration(minutes: 15);

/// The moment the user must leave to reach the first timeline item on time:
/// the item's time minus live travel duration.
DateTime departureTime({required DateTime firstItem, required Duration travel}) =>
    firstItem.subtract(travel);

/// When to fire the "leave in 15 minutes" reminder: [kDepartureWarning] before
/// the departure moment.
DateTime remindAt(DateTime departure) => departure.subtract(kDepartureWarning);
