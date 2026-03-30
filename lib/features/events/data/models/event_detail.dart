import 'event_member.dart';

// ── Supporting types ──────────────────────────────────────────────────────────

class EventAttachment {
  const EventAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
  });
  final int id;
  final String filename;
  final String mimeType;
  final int fileSize;

  factory EventAttachment.fromJson(Map<String, dynamic> json) => EventAttachment(
        id: (json['id'] as num).toInt(),
        filename: json['filename'] as String? ?? '',
        mimeType: json['mime_type'] as String? ?? '',
        fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      );

  String get formattedSize {
    double bytes = fileSize.toDouble();
    const units = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    while (bytes > 1024 && i < units.length - 1) {
      bytes /= 1024;
      i++;
    }
    return '${bytes.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }
}

class EventTimelineEntry {
  const EventTimelineEntry({required this.title, this.time});
  final String title;
  final String? time; // e.g. "2026-04-15T19:00:00" or "19:00"

  factory EventTimelineEntry.fromJson(Map<String, dynamic> json) =>
      EventTimelineEntry(
        title: json['title'] as String? ?? '',
        time: json['time'] as String?,
      );
}

class EventContact {
  const EventContact({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role,
  });
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? role;

  factory EventContact.fromJson(Map<String, dynamic> json) => EventContact(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        role: json['role'] as String?,
      );
}

class WeddingDance {
  const WeddingDance({required this.title, this.data});
  final String title;
  final String? data;

  factory WeddingDance.fromJson(Map<String, dynamic> json) => WeddingDance(
        title: json['title'] as String? ?? '',
        data: json['data'] as String?,
      );
}

class WeddingDetail {
  const WeddingDetail({this.onsite, required this.dances});
  final bool? onsite;
  final List<WeddingDance> dances;

  factory WeddingDetail.fromJson(Map<String, dynamic> json) {
    final rawDances = json['dances'];
    final dances = rawDances is List
        ? rawDances.cast<Map<String, dynamic>>().map(WeddingDance.fromJson).toList()
        : <WeddingDance>[];
    return WeddingDetail(
      onsite: json['onsite'] as bool?,
      dances: dances,
    );
  }
}

class PerformanceSong {
  const PerformanceSong({this.title, this.url});
  final String? title;
  final String? url;

  factory PerformanceSong.fromJson(Map<String, dynamic> json) => PerformanceSong(
        title: json['title'] as String?,
        url: json['url'] as String?,
      );
}

class PerformanceChart {
  const PerformanceChart({required this.title, this.composer});
  final String title;
  final String? composer;

  factory PerformanceChart.fromJson(Map<String, dynamic> json) => PerformanceChart(
        title: json['title'] as String? ?? '',
        composer: json['composer'] as String?,
      );
}

class Performance {
  const Performance({this.notes, required this.songs, required this.charts});
  final String? notes;
  final List<PerformanceSong> songs;
  final List<PerformanceChart> charts;

  factory Performance.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'];
    final songs = rawSongs is List
        ? rawSongs.cast<Map<String, dynamic>>().map(PerformanceSong.fromJson).toList()
        : <PerformanceSong>[];
    final rawCharts = json['charts'];
    final charts = rawCharts is List
        ? rawCharts.cast<Map<String, dynamic>>().map(PerformanceChart.fromJson).toList()
        : <PerformanceChart>[];
    return Performance(
      notes: json['notes'] as String?,
      songs: songs,
      charts: charts,
    );
  }
}

class LodgingItem {
  const LodgingItem({required this.type, required this.title, this.data});
  final String type;
  final String title;
  final dynamic data;

  factory LodgingItem.fromJson(Map<String, dynamic> json) => LodgingItem(
        type: json['type'] as String? ?? 'text',
        title: json['title'] as String? ?? '',
        data: json['data'],
      );
}

// ── EventDetail ───────────────────────────────────────────────────────────────

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
    required this.timeline,
    this.isPublic,
    this.attire,
    this.outside,
    this.backlineProvided,
    this.productionNeeded,
    required this.lodging,
    this.performance,
    this.wedding,
    required this.contacts,
    required this.attachments,
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

  final bool canWrite;

  final int? liveSessionId;
  final List<EventMember> members;

  // additional_data fields
  final List<EventTimelineEntry> timeline;
  final bool? isPublic;
  final String? attire;
  final bool? outside;
  final bool? backlineProvided;
  final bool? productionNeeded;
  final List<LodgingItem> lodging;
  final Performance? performance;
  final WeddingDetail? wedding;
  final List<EventContact> contacts;
  final List<EventAttachment> attachments;

  factory EventDetail.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers.cast<Map<String, dynamic>>().map(EventMember.fromJson).toList()
        : <EventMember>[];

    final rawTimeline = json['timeline'];
    final timeline = rawTimeline is List
        ? rawTimeline.cast<Map<String, dynamic>>().map(EventTimelineEntry.fromJson).toList()
        : <EventTimelineEntry>[];

    final rawLodging = json['lodging'];
    final lodging = rawLodging is List
        ? rawLodging.cast<Map<String, dynamic>>().map(LodgingItem.fromJson).toList()
        : <LodgingItem>[];

    final rawContacts = json['contacts'];
    final contacts = rawContacts is List
        ? rawContacts.cast<Map<String, dynamic>>().map(EventContact.fromJson).toList()
        : <EventContact>[];

    final rawPerformance = json['performance'];
    final performance = rawPerformance is Map<String, dynamic>
        ? Performance.fromJson(rawPerformance)
        : null;

    final rawWedding = json['wedding'];
    final wedding = rawWedding is Map<String, dynamic>
        ? WeddingDetail.fromJson(rawWedding)
        : null;

    final rawAttachments = json['attachments'];
    final attachments = rawAttachments is List
        ? rawAttachments.cast<Map<String, dynamic>>().map(EventAttachment.fromJson).toList()
        : <EventAttachment>[];

    return EventDetail(
      id: (json['id'] as num).toInt(),
      key: json['key'] as String,
      title: json['title'] as String,
      date: json['date'] as String,
      time: _toHHmm(json['time'] as String?),
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
      timeline: timeline,
      isPublic: json['is_public'] as bool?,
      attire: json['attire'] as String?,
      outside: json['outside'] as bool?,
      backlineProvided: json['backline_provided'] as bool?,
      productionNeeded: json['production_needed'] as bool?,
      lodging: lodging,
      performance: performance,
      wedding: wedding,
      contacts: contacts,
      attachments: attachments,
    );
  }

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
      other is EventDetail && runtimeType == other.runtimeType && key == other.key;

  @override
  int get hashCode => key.hashCode;
}

/// Normalises a time string from the API (e.g. "20:00:00" or "20:00") to "HH:mm"
/// as required by the backend's `date_format:H:i` validation rule.
String? _toHHmm(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
}
