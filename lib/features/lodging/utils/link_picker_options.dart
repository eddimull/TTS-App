/// One selectable row in the booking/event link pickers.
class LinkOption {
  const LinkOption(this.id, this.label, [this.date]);
  final int? id;
  final String label;
  final DateTime? date;
}

DateTime? _day(DateTime? dt) =>
    dt == null ? null : DateTime(dt.year, dt.month, dt.day);

const _nearbyDays = 14;

/// Groups options around a stay: "During your stay" (inside
/// check-in..check-out), "Nearby" (±14 days of check-in), then everything
/// else. Empty groups are omitted. Without a check-in, one unlabeled group
/// sorted date-ascending, undated entries last.
List<({String label, List<LinkOption> options})> groupLinkOptions(
  List<LinkOption> options,
  DateTime? checkIn,
  DateTime? checkOut,
) {
  final inDay = _day(checkIn);
  final outDay = _day(checkOut) ?? inDay;

  int ascending(LinkOption a, LinkOption b) {
    final da = _day(a.date);
    final db = _day(b.date);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  if (inDay == null) {
    final sorted = [...options]..sort(ascending);
    return [(label: '', options: sorted)];
  }

  int distance(LinkOption o) => _day(o.date)!.difference(inDay).inDays.abs();

  final during = <LinkOption>[];
  final nearby = <LinkOption>[];
  final rest = <LinkOption>[];
  for (final o in options) {
    final day = _day(o.date);
    if (day != null && !day.isBefore(inDay) && !day.isAfter(outDay!)) {
      during.add(o);
    } else if (day != null && distance(o) <= _nearbyDays) {
      nearby.add(o);
    } else {
      rest.add(o);
    }
  }
  during.sort((a, b) => distance(a).compareTo(distance(b)));
  nearby.sort((a, b) => distance(a).compareTo(distance(b)));
  rest.sort(ascending);

  return [
    (label: 'During your stay', options: during),
    (label: 'Nearby', options: nearby),
    (label: 'Everything else', options: rest),
  ].where((g) => g.options.isNotEmpty).toList();
}
