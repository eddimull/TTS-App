class EventSummary {
  const EventSummary({
    this.id,
    required this.key,
    required this.title,
    required this.date,
    this.time,
    this.eventType,
    required this.eventSource,
    this.venueName,
    this.venueAddress,
    this.status,
    this.liveSessionId,
  });

  final int? id;
  final String key;
  final String title;

  /// ISO date string, e.g. "2026-04-15".
  final String date;

  /// Time string, e.g. "19:00", or null.
  final String? time;

  final String? eventType;

  /// One of "booking", "rehearsal", or "band_event".
  final String eventSource;

  final String? venueName;
  final String? venueAddress;
  final String? status;
  final int? liveSessionId;

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    return EventSummary(
      id: json['id'] == null ? null : (json['id'] as num).toInt(),
      key: json['key'] as String,
      title: json['title'] as String,
      date: json['date'] as String,
      time: json['time'] as String?,
      eventType: json['event_type'] as String?,
      eventSource: json['event_source'] as String? ?? 'band_event',
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
      status: json['status'] as String?,
      liveSessionId: json['live_session_id'] == null
          ? null
          : (json['live_session_id'] as num).toInt(),
    );
  }

  /// Returns true when this event is a rehearsal.
  bool get isRehearsal =>
      eventSource == 'rehearsal' || eventSource == 'rehearsal_schedule';

  /// Parses [date] into a [DateTime]. Returns [DateTime.now()] as a fallback.
  DateTime get parsedDate {
    try {
      return DateTime.parse(date);
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  String toString() =>
      'EventSummary(id: $id, key: $key, title: $title, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventSummary &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}
