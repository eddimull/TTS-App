import 'event_member.dart';

class EventDetail {
  const EventDetail({
    required this.id,
    required this.key,
    required this.title,
    required this.date,
    this.time,
    this.notes,
    this.eventType,
    this.eventTypeId,
    this.venueName,
    this.venueAddress,
    this.status,
    this.eventableType,
    this.eventableId,
    required this.canWrite,
    this.liveSessionId,
    required this.members,
  });

  final int id;
  final String key;
  final String title;

  /// ISO date string, e.g. "2026-04-15".
  final String date;

  /// Time string, e.g. "19:00", or null.
  final String? time;

  final String? notes;
  final String? eventType;
  final int? eventTypeId;
  final String? venueName;
  final String? venueAddress;
  final String? status;

  /// Polymorphic type, e.g. "Bookings" or "BandEvents".
  final String? eventableType;
  final int? eventableId;

  /// Whether the current user has write access to this event.
  final bool canWrite;

  final int? liveSessionId;
  final List<EventMember> members;

  factory EventDetail.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers
            .cast<Map<String, dynamic>>()
            .map(EventMember.fromJson)
            .toList()
        : <EventMember>[];

    return EventDetail(
      id: (json['id'] as num).toInt(),
      key: json['key'] as String,
      title: json['title'] as String,
      date: json['date'] as String,
      time: json['time'] as String?,
      notes: json['notes'] as String?,
      eventType: json['event_type'] as String?,
      eventTypeId: json['event_type_id'] == null
          ? null
          : (json['event_type_id'] as num).toInt(),
      venueName: json['venue_name'] as String?,
      venueAddress: json['venue_address'] as String?,
      status: json['status'] as String?,
      eventableType: json['eventable_type'] as String?,
      eventableId: json['eventable_id'] == null
          ? null
          : (json['eventable_id'] as num).toInt(),
      canWrite: (json['can_write'] as bool?) ?? false,
      liveSessionId: json['live_session_id'] == null
          ? null
          : (json['live_session_id'] as num).toInt(),
      members: members,
    );
  }

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
      'EventDetail(id: $id, key: $key, title: $title, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventDetail &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}
