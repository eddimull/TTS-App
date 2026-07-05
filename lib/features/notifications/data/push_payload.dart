/// The kind of push the backend sent.
enum PushType { reminder8h, departure, rehearsalCancelled, rehearsalRestored, unknown }

/// Stable notification id for an event's "departure" slot. The push-rendered
/// notification and the locally-scheduled enriched one MUST use this same id so
/// one replaces/cancels the other instead of stacking duplicates.
int departureNotificationId(String eventKey) =>
    Object.hash(eventKey, PushType.departure).toUnsigned(31);

PushType _typeFromString(String? raw) {
  switch (raw) {
    case 'event_reminder_8h':
      return PushType.reminder8h;
    case 'event_departure':
      return PushType.departure;
    case 'rehearsal_cancelled':
      return PushType.rehearsalCancelled;
    case 'rehearsal_restored':
      return PushType.rehearsalRestored;
    default:
      return PushType.unknown;
  }
}

/// Typed view of an incoming FCM `data` map. Tolerant of missing fields.
class PushPayload {
  const PushPayload({
    required this.type,
    required this.eventKey,
    this.title,
    this.venueAddress,
    this.firstItemTitle,
    this.firstItemTime,
    this.showTime,
    this.body,
    this.rehearsalId,
  });

  final PushType type;
  final String eventKey;

  /// Human-facing event title the backend sends (used as the notification
  /// title). Distinct from [venueAddress].
  final String? title;
  final String? venueAddress;
  final String? firstItemTitle;
  final String? firstItemTime;
  final String? showTime;
  final String? body;
  final String? rehearsalId;

  factory PushPayload.fromData(Map<String, dynamic> data) {
    String? str(String key) {
      final v = data[key];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    return PushPayload(
      type: _typeFromString(data['type']?.toString()),
      eventKey: str('eventKey') ?? '',
      title: str('title'),
      venueAddress: str('venueAddress'),
      firstItemTitle: str('firstItemTitle'),
      firstItemTime: str('firstItemTime'),
      showTime: str('showTime'),
      body: str('body'),
      rehearsalId: str('rehearsalId'),
    );
  }

  /// Stable id for deduping notifications: one slot per entity+type. Departure
  /// keeps its shared-slot contract with the enrichment scheduler; everything
  /// else hashes its best entity key (eventKey, else rehearsalId) with its type.
  int get notificationId {
    if (type == PushType.departure) return departureNotificationId(eventKey);
    final entity = eventKey.isNotEmpty ? eventKey : (rehearsalId ?? '');
    return Object.hash(entity, type).toUnsigned(31);
  }
}
