// ── Inline stubs ──────────────────────────────────────────────────────────────

class ScheduleStub {
  const ScheduleStub({
    required this.id,
    required this.name,
    this.locationName,
  });

  final int id;
  final String name;
  final String? locationName;

  factory ScheduleStub.fromJson(Map<String, dynamic> json) {
    return ScheduleStub(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      locationName: json['location_name'] as String?,
    );
  }

  @override
  String toString() => 'ScheduleStub(id: $id, name: $name)';
}

class AssociatedBooking {
  const AssociatedBooking({
    required this.id,
    required this.name,
    required this.date,
  });

  final int id;
  final String name;
  final String date;

  factory AssociatedBooking.fromJson(Map<String, dynamic> json) {
    return AssociatedBooking(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      date: json['date'] as String,
    );
  }

  @override
  String toString() => 'AssociatedBooking(id: $id, name: $name, date: $date)';
}

// ── Full rehearsal detail ─────────────────────────────────────────────────────

class RehearsalDetail {
  const RehearsalDetail({
    required this.id,
    this.date,
    this.time,
    this.venueName,
    required this.isCancelled,
    this.notes,
    this.eventKey,
    required this.schedule,
    required this.associatedBookings,
  });

  final int id;

  /// ISO date string, e.g. "2026-04-16", or null.
  final String? date;

  /// Time string, e.g. "19:00", or null.
  final String? time;

  final String? venueName;
  final bool isCancelled;
  final String? notes;
  final String? eventKey;
  final ScheduleStub schedule;
  final List<AssociatedBooking> associatedBookings;

  factory RehearsalDetail.fromJson(Map<String, dynamic> json) {
    final rawBookings = json['associated_bookings'];
    final associatedBookings = rawBookings is List
        ? rawBookings
            .cast<Map<String, dynamic>>()
            .map(AssociatedBooking.fromJson)
            .toList()
        : <AssociatedBooking>[];

    return RehearsalDetail(
      id: (json['id'] as num).toInt(),
      date: json['date'] as String?,
      time: json['time'] as String?,
      venueName: json['venue_name'] as String?,
      isCancelled: (json['is_cancelled'] as bool?) ?? false,
      notes: json['notes'] as String?,
      eventKey: json['event_key'] as String?,
      schedule:
          ScheduleStub.fromJson(json['schedule'] as Map<String, dynamic>),
      associatedBookings: associatedBookings,
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
  String toString() => 'RehearsalDetail(id: $id, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RehearsalDetail &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
