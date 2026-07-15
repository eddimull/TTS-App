import '../../../auth/data/models/band_summary.dart';

String _normalizeEventSource(String? raw) {
  // Backend emits both 'rehearsal' (completed/scheduled) and
  // 'rehearsal_schedule' (virtual recurring) — collapse to one bucket so
  // filtering and rendering only have to handle three values.
  if (raw == 'rehearsal_schedule') return 'rehearsal';
  return raw ?? 'band_event';
}

class EventSummary {
  const EventSummary({
    this.id,
    required this.key,
    required this.title,
    required this.date,
    this.time,
    this.startTime,
    this.endTime,
    this.price,
    this.eventType,
    required this.eventSource,
    this.venueName,
    this.venueAddress,
    this.status,
    this.liveSessionId,
    this.rosterStatus,
    this.band,
    this.unreadCommentCount = 0,
    this.isCancelled = false,
  });

  final int? id;
  final String key;
  final String title;

  /// ISO date string, e.g. "2026-04-15".
  final String date;

  /// Legacy single time field, e.g. "19:00", or null. Maintained for
  /// backward compat with older payloads that haven't switched to the
  /// split start_time / end_time shape. New code should read [startTime].
  final String? time;

  /// Event start time, e.g. "19:00", or null.
  final String? startTime;

  /// Event end time, e.g. "22:00", or null.
  final String? endTime;

  /// Per-event price string, e.g. "1500.00", or null when not itemized.
  final String? price;

  final String? eventType;

  /// One of "booking", "rehearsal", or "band_event".
  final String eventSource;

  final String? venueName;
  final String? venueAddress;
  final String? status;
  final int? liveSessionId;

  /// One of "green", "yellow", "red", "none", or null.
  final String? rosterStatus;

  /// Optional nested band identity for rendering a band/personal chip on the
  /// dashboard. Absent on legacy payloads.
  final BandSummary? band;

  /// Unread comments in this event's topic thread. 0 on legacy payloads
  /// that don't send unread_comment_count.
  final int unreadCommentCount;

  /// True when this event is a cancelled rehearsal. False on legacy
  /// payloads that don't send is_cancelled.
  final bool isCancelled;

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    final rawBand = json['band'];
    final band = rawBand is Map<String, dynamic>
        ? BandSummary.fromJson(rawBand)
        : null;

    return EventSummary(
      id: json['id'] == null ? null : (json['id'] as num).toInt(),
      key: json['key'] as String,
      title: json['title'] as String,
      date: json['date'] as String,
      time: json['time'] as String?,
      startTime: (json['start_time'] as String?) ?? (json['time'] as String?),
      endTime: json['end_time'] as String?,
      price: json['price'] as String?,
      eventType: json['event_type'] as String?,
      eventSource: _normalizeEventSource(json['event_source'] as String?),
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
      status: json['status'] as String?,
      liveSessionId: json['live_session_id'] == null
          ? null
          : (json['live_session_id'] as num).toInt(),
      rosterStatus: json['roster_status'] as String?,
      band: band,
      unreadCommentCount: (json['unread_comment_count'] as num?)?.toInt() ?? 0,
      isCancelled: (json['is_cancelled'] as bool?) ?? false,
    );
  }

  /// Returns the asset path for the gig type icon, or null for rehearsals.
  ///
  /// Keys mirror the web app's [CardIcon.vue] mapping, normalized to
  /// lowercase with whitespace stripped so that "Bar Gig", "BAR GIG", and
  /// "bar gig" all resolve to the same icon.
  String? get gigIconPath {
    if (isRehearsal) return null;
    final type = eventType?.toLowerCase().replaceAll(' ', '') ?? '';
    const base = 'assets/images/gigIcons';
    return switch (type) {
      'bargig' => '$base/bar.png',
      'casino' => '$base/casino.png',
      'charity' => '$base/charity.png',
      'festival' => '$base/festival.png',
      'mardigrasball' => '$base/mardiGras.png',
      'privateparty' => '$base/private.png',
      'specialevent' => '$base/special.png',
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
