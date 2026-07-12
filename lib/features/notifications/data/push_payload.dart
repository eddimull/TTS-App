import 'notification_channels.dart';
import 'push_route.dart';

/// The kind of push the backend sent.
enum PushType { reminder8h, departure, rehearsalCancelled, rehearsalRestored, chatMessage, unknown }

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
    case 'chat_message':
      return PushType.chatMessage;
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
    this.conversationId,
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
  final String? conversationId;

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
      conversationId: str('conversationId'),
    );
  }

  /// Stable id for deduping notifications: one slot per entity+type. Departure
  /// keeps its shared-slot contract with the enrichment scheduler; everything
  /// else hashes its best entity key (eventKey, else conversationId, else rehearsalId) with its type.
  int get notificationId {
    if (type == PushType.departure) return departureNotificationId(eventKey);
    final entity = eventKey.isNotEmpty
        ? eventKey
        : (conversationId ?? rehearsalId ?? '');
    return Object.hash(entity, type).toUnsigned(31);
  }
}

/// Pure description of a notification to render: no platform channel types,
/// so it can be built and unit-tested without flutter_local_notifications.
class BackgroundNotificationSpec {
  const BackgroundNotificationSpec({
    required this.id,
    required this.title,
    required this.body,
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    this.route,
  });

  final int id;
  final String title;
  final String body;
  final String channelId;
  final String channelName;
  final String channelDescription;

  /// In-app route to open when the user taps this notification, or null when
  /// the type has no destination (see [routeForPushData]). Passed through as
  /// the flutter_local_notifications payload so a tap can deep-link even
  /// though this spec was built inside FCM's isolated background handler.
  final String? route;
}

/// Pure mapper: an incoming FCM background-isolate data payload → what to
/// render, or null when this type has no background rendering (e.g. reminder
/// pushes, which arrive hybrid/OS-rendered, or unknown types).
///
/// Scope: `chat_message` only for now — the backend sends chat pushes
/// data-only, so without this the background isolate shows nothing on
/// Android. Kept free of Riverpod/plugin imports so it runs safely in the
/// separate background isolate FCM spins up for `onBackgroundMessage`.
BackgroundNotificationSpec? buildBackgroundNotification(
  Map<String, dynamic> data,
) {
  final payload = PushPayload.fromData(data);
  if (payload.type != PushType.chatMessage) return null;

  return BackgroundNotificationSpec(
    id: payload.notificationId,
    title: payload.title ?? 'TTS Bandmate',
    body: payload.body ?? '',
    channelId: BandUpdatesChannel.id,
    channelName: BandUpdatesChannel.name,
    channelDescription: BandUpdatesChannel.description,
    route: routeForPushData(data),
  );
}
