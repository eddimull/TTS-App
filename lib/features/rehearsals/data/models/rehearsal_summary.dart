class RehearsalSummary {
  const RehearsalSummary({
    this.id,
    this.date,
    this.time,
    this.venueName,
    required this.isCancelled,
    this.notes,
    this.eventKey,
    this.isVirtual = false,
  });

  final int? id;
  final bool isVirtual;

  /// ISO date string, e.g. "2026-04-16", or null.
  final String? date;

  /// Time string, e.g. "19:00", or null.
  final String? time;

  final String? venueName;
  final bool isCancelled;
  final String? notes;
  final String? eventKey;

  factory RehearsalSummary.fromJson(Map<String, dynamic> json) {
    return RehearsalSummary(
      id: json['id'] == null ? null : (json['id'] as num).toInt(),
      date: json['date'] as String?,
      time: json['time'] as String?,
      venueName: json['venue_name'] as String?,
      isCancelled: (json['is_cancelled'] as bool?) ?? false,
      notes: json['notes'] as String?,
      eventKey: json['event_key'] as String?,
      isVirtual: (json['is_virtual'] as bool?) ?? false,
    );
  }

  /// Parses [date] into a [DateTime]. Returns [DateTime.now()] as a fallback.
  DateTime get parsedDate {
    if (date == null) return DateTime.now();
    try {
      return DateTime.parse(date!);
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  String toString() => 'RehearsalSummary(id: $id, date: $date)';
}
