import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tts_bandmate/core/network/geocoding.dart';

import '../../../core/network/api_client.dart';
import '../data/device_repository.dart';
import '../data/event_first_item.dart' show resolveFirstItem;
import '../data/push_payload.dart' show departureNotificationId;
import '../data/routes_client.dart';
import '../services/enrichment_service.dart';
import '../services/location_service.dart';
import '../services/push_service.dart';
import '../../events/providers/events_provider.dart';
import '../../events/data/events_repository.dart';
import '../../../shared/providers/selected_band_provider.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepository(ref.watch(apiClientProvider).dio);
});

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(FlutterLocalNotificationsPlugin());
});

/// Platform string the backend expects, or null when push is unsupported.
String? _platformName() {
  if (kIsWeb) return null;
  if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
  if (defaultTargetPlatform == TargetPlatform.android) return 'android';
  return null;
}

/// Coordinates token lifecycle: call [registerCurrentToken] after login and
/// [deregisterCurrentToken] on logout.
class PushRegistrar {
  PushRegistrar(this._ref);
  final Ref _ref;

  bool _watchingRefresh = false;

  Future<void> registerCurrentToken() async {
    final platform = _platformName();
    if (platform == null) return; // unsupported platform: no-op
    final push = _ref.read(pushServiceProvider);
    await push.init();
    await push.requestPermission();
    push.listenForeground();
    push.onDeparturePush = (payload) async {
      final firstTime = payload.firstItemTime;
      if (firstTime == null) return;
      final first = DateTime.tryParse(firstTime);
      if (first == null) return;
      await enrichEventFromPush(
        _ref,
        eventKey: payload.eventKey,
        eventTitle: payload.title ?? 'Event today',
        venueAddress: payload.venueAddress ?? '',
        firstItemTitle: payload.firstItemTitle ?? 'your event',
        firstItem: first,
      );
    };
    _watchTokenRefresh(push, platform);
    final token = await push.token();
    if (token == null) return;
    await _ref.read(deviceRepositoryProvider).register(
          token: token,
          platform: platform,
        );
  }

  /// Re-register with the backend when FCM rotates the token (reinstall,
  /// restore, periodic refresh), so the "safety net" push never silently
  /// breaks. Idempotent: only one subscription per process.
  void _watchTokenRefresh(PushService push, String platform) {
    if (_watchingRefresh) return;
    _watchingRefresh = true;
    push.onTokenRefresh.listen((token) async {
      try {
        await _ref.read(deviceRepositoryProvider).register(
              token: token,
              platform: platform,
            );
      } catch (_) {
        // Best-effort; the next login re-registers anyway.
      }
    });
  }

  Future<void> deregisterCurrentToken() async {
    if (_platformName() == null) return;
    final push = _ref.read(pushServiceProvider);
    final token = await push.token();
    if (token == null) return;
    try {
      await _ref.read(deviceRepositoryProvider).deregister(token);
    } catch (_) {
      // Best-effort: logout should not fail if deregistration does.
    }
  }
}

final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  return PushRegistrar(ref);
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final routesClientProvider = Provider<RoutesClient>((ref) {
  return RoutesClient();
});

/// Enrich today's rostered events: for each event today the user plays that has
/// a venue and a first timeline item, compute live travel time and schedule (or
/// suppress) the precise "leave in 15 min" local notification. Best-effort;
/// any failure leaves the server's time-based push as the floor.
Future<void> enrichTodaysEvents(WidgetRef ref, {DateTime? clock}) async {
  final now = clock ?? DateTime.now();

  // Cheap no-op checks first: don't prompt for location / hit GPS when there's
  // nothing to enrich (e.g. no band selected yet on cold start / resume).
  final bandId = ref.read(selectedBandProvider).value;
  if (bandId == null) return;

  final location = ref.read(locationServiceProvider);
  final grant = await location.ensurePermission();
  if (grant == LocationGrant.denied) return;

  final origin = await location.current();
  if (origin == null) return;

  final today = _ymd(now);
  final events = await ref.read(
    bandEventsProvider(BandEventsParams(bandId: bandId, from: today, to: today)).future,
  );

  final repo = ref.read(eventsRepositoryProvider);
  final routes = ref.read(routesClientProvider);
  final push = ref.read(pushServiceProvider);

  for (final summary in events) {
    if (summary.date != today) continue;
    if (!_isRostered(summary.rosterStatus)) continue;
    final address = summary.venueAddress;
    if (address == null || address.isEmpty) continue;

    // Best-effort per event: a failure (e.g. getEventDetail throwing) must not
    // abandon enrichment for the remaining events of the day.
    try {
      final detail = await repo.getEventDetail(summary.key);
      final first = resolveFirstItem(detail.timeline);
      if (first == null) continue;

      final travel =
          await routes.driveDuration(origin: origin, destinationAddress: address);
      if (travel == null) continue;

      final venuePoint = await geocodeAddress(address);
      final meters = venuePoint == null
          ? double.infinity
          : location.distanceMeters(origin, venuePoint);

      await enrich(
        EnrichmentInput(
          notificationId: departureNotificationId(summary.key),
          eventTitle: summary.title,
          venue: summary.venueName ?? address,
          firstItemTitle: first.title,
          firstItem: first.time,
          now: now,
          origin: origin,
          travel: travel,
          metersToVenue: meters,
        ),
        push,
      );
    } catch (_) {
      // Skip this event; the server's time-based push remains the floor.
      continue;
    }
  }
}

/// Enrich a single event from an `event_departure` data push. Best-effort.
Future<void> enrichEventFromPush(
  Ref ref, {
  required String eventKey,
  required String eventTitle,
  required String venueAddress,
  required String firstItemTitle,
  required DateTime firstItem,
  DateTime? clock,
}) async {
  final now = clock ?? DateTime.now();
  final location = ref.read(locationServiceProvider);
  if (await location.ensurePermission() == LocationGrant.denied) return;
  final origin = await location.current();
  if (origin == null) return;

  final routes = ref.read(routesClientProvider);
  final travel =
      await routes.driveDuration(origin: origin, destinationAddress: venueAddress);
  if (travel == null) return;

  final venuePoint = await geocodeAddress(venueAddress);
  final meters =
      venuePoint == null ? double.infinity : location.distanceMeters(origin, venuePoint);

  await enrich(
    EnrichmentInput(
      notificationId: departureNotificationId(eventKey),
      eventTitle: eventTitle,
      venue: venueAddress,
      firstItemTitle: firstItemTitle,
      firstItem: firstItem,
      now: now,
      origin: origin,
      travel: travel,
      metersToVenue: meters,
    ),
    ref.read(pushServiceProvider),
  );
}

bool _isRostered(String? status) => status == 'green' || status == 'yellow';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
