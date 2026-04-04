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
    this.rosterStatus,
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

  /// One of "green", "yellow", "red", "none", or null.
  final String? rosterStatus;

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
      rosterStatus: json['roster_status'] as String?,
    );
  }

  /// Returns the asset path for the gig type icon, or null for rehearsals.
  String? get gigIconPath {
    if (isRehearsal) return null;
    final type = eventType?.toLowerCase().replaceAll(' ', '') ?? '';
    const base = 'assets/images/gigIcons';
    return switch (type) {
      'bar' => '$base/bar.png',
      'casino' => '$base/casino.png',
      'charity' => '$base/charity.png',
      'festival' => '$base/festival.png',
      'mardigras' => '$base/mardiGras.png',
      'private' => '$base/private.png',
      'special' => '$base/special.png',
      'wedding' => '$base/wedding.png',
      _ => '$base/other.png',
    };
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
