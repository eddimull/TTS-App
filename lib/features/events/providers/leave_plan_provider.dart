import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/providers/selected_band_provider.dart';
import '../../account/providers/account_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/network/geocoding.dart';
import '../../notifications/data/routes_client.dart';
import '../../notifications/providers/notifications_provider.dart'
    show locationServiceProvider, routesClientProvider;
import '../../notifications/services/location_service.dart';
import '../data/leave_plan.dart';
import 'events_provider.dart';

const String leaveStartKey = 'leave_start';
const String leaveEarlyByKey = 'leave_early_min';
const String _driveCachePrefix = 'leave_drive:';

/// Where the user leaves from and how early they like to arrive. Stored on
/// this phone only, for every event.
class LeaveSettings {
  const LeaveSettings({this.start, this.earlyBy = defaultEarlyBy});
  final LeaveStart? start;
  final Duration earlyBy;
}

class LeaveSettingsNotifier extends AsyncNotifier<LeaveSettings> {
  @override
  Future<LeaveSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(leaveStartKey);
    final mins = prefs.getInt(leaveEarlyByKey);
    return LeaveSettings(
      start: LeaveStart.values.where((s) => s.name == name).firstOrNull,
      earlyBy: mins == null ? defaultEarlyBy : Duration(minutes: mins),
    );
  }

  Future<void> setStart(LeaveStart start) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(leaveStartKey, start.name);
    final current = state.value ?? const LeaveSettings();
    state = AsyncData(LeaveSettings(start: start, earlyBy: current.earlyBy));
  }

  Future<void> setEarlyBy(Duration earlyBy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(leaveEarlyByKey, earlyBy.inMinutes);
    final current = state.value ?? const LeaveSettings();
    state = AsyncData(LeaveSettings(start: current.start, earlyBy: earlyBy));
  }
}

final leaveSettingsProvider =
    AsyncNotifierProvider<LeaveSettingsNotifier, LeaveSettings>(
        LeaveSettingsNotifier.new);

/// Typical-traffic drive times, kept for the day so opening the event doesn't
/// call Google every time. [route] identifies the addresses, so a changed
/// address isn't served a stale time.
class LeaveDriveCache {
  LeaveDriveCache(this._prefs);
  final SharedPreferences _prefs;

  static String _key(String eventKey, LeaveStart start, DateTime day) =>
      '$_driveCachePrefix$eventKey:${start.name}:'
      '${day.year}-${day.month}-${day.day}';

  Duration? get(String eventKey, LeaveStart start, DateTime day, String route) {
    final raw = _prefs.getString(_key(eventKey, start, day));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['route'] != route) return null;
      return Duration(seconds: (json['s'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  /// Saves [drive] and drops entries from earlier days.
  Future<void> put(String eventKey, LeaveStart start, DateTime day,
      String route, Duration drive) async {
    final key = _key(eventKey, start, day);
    final suffix = ':${day.year}-${day.month}-${day.day}';
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(_driveCachePrefix) && !k.endsWith(suffix)) {
        await _prefs.remove(k);
      }
    }
    await _prefs.setString(
        key, jsonEncode({'route': route, 's': drive.inSeconds}));
  }
}

bool get _locationSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// The user's home address from their profile, or null.
Future<String?> _homeAddress(Ref ref) async {
  try {
    final account = await ref.watch(accountProvider.future);
    final p = account.profile;
    final state =
        account.states.where((s) => s.id == p.stateId).firstOrNull?.name;
    if (p.address1 == null || p.address1!.trim().isEmpty) return null;
    return joinAddress([p.address1, p.address2, p.city, state, p.zip]);
  } catch (_) {
    return null;
  }
}

/// The selected band's address (gear pickup), or null.
String? _bandAddress(Ref ref) {
  final bandId = ref.watch(selectedBandProvider).value;
  final auth = ref.watch(authProvider).value;
  if (bandId == null || auth is! AuthAuthenticated) return null;
  final band = auth.bands.where((b) => b.id == bandId).firstOrNull;
  if (band == null || band.address == null || band.address!.trim().isEmpty) {
    return null;
  }
  return joinAddress([band.address, band.city, band.state, band.zip]);
}

/// Leave times need Google Routes, so they're off in builds without a key.
final leaveTimesEnabledProvider =
    Provider<bool>((ref) => AppConfig.googlePlacesApiKey.isNotEmpty);

/// When to leave for an event. Null when [leaveRowApplies] is false or leave
/// times are off.
final leavePlanProvider = FutureProvider.autoDispose
    .family<LeavePlan?, String>((ref, eventKey) async {
  final event = await ref.watch(eventDetailProvider(eventKey).future);
  final now = clock.now();
  if (!ref.watch(leaveTimesEnabledProvider) || !leaveRowApplies(event, now)) {
    return null;
  }
  final venue = event.venueAddress!.trim();
  final target = leaveTarget(event)!;

  final settings = await ref.watch(leaveSettingsProvider.future);
  final home = await _homeAddress(ref);
  final band = _bandAddress(ref);
  final lodging = event.lodgings
      .where((l) => l.address != null && l.address!.trim().isNotEmpty)
      .firstOrNull;
  final available = {
    if (home != null) LeaveStart.home,
    if (band != null) LeaveStart.gearPickup,
    if (lodging != null) LeaveStart.hotel,
    if (_locationSupported) LeaveStart.here,
  };
  final start = resolveStart(settings.start, available);
  final live = isLeaveDay(event, now);
  final routes = ref.read(routesClientProvider);
  final location = ref.read(locationServiceProvider);
  final destination = RoutePlace.address(venue);

  LeavePlan plan({Duration? drive, bool fromHere = false}) {
    final rounded = drive == null ? null : roundDrive(drive);
    return LeavePlan(
      target: target,
      earlyBy: settings.earlyBy,
      available: available,
      start: start,
      hotelName: lodging?.name,
      drive: rounded,
      leaveAt: rounded == null
          ? null
          : leaveBy(
              arriveBy: target.at, earlyBy: settings.earlyBy, drive: rounded),
      live: live,
      fromHere: fromHere,
    );
  }

  Future<GeoPoint?> here() async {
    if (!_locationSupported) return null;
    if (await location.ensurePermission() == LocationGrant.denied) return null;
    return location.current();
  }

  // Gig day: from wherever the phone is, in live traffic.
  if (live) {
    final origin = await here();
    if (origin != null) {
      final drive = await routes.routeDuration(
          origin: RoutePlace.point(origin), destination: destination);
      if (drive != null) return plan(drive: drive, fromHere: true);
    }
  }
  if (start == null) return plan();

  RoutePlace? origin;
  var via = const <RoutePlace>[];
  String? route;
  switch (start) {
    case LeaveStart.home:
      origin = RoutePlace.address(home!);
      route = home;
    case LeaveStart.gearPickup:
      if (home != null) {
        origin = RoutePlace.address(home);
        via = [RoutePlace.address(band!)];
      } else {
        origin = RoutePlace.address(band!);
      }
      route = '$home|$band';
    case LeaveStart.hotel:
      origin = RoutePlace.address(lodging!.address!);
      route = lodging.address;
    case LeaveStart.here:
      final point = await here();
      origin = point == null ? null : RoutePlace.point(point);
  }
  if (origin == null) return plan();
  route = route == null ? null : '$route>$venue';

  // Typical traffic at about when they'd leave; Google only takes future
  // departure times.
  final planned = target.at
      .subtract(settings.earlyBy)
      .subtract(const Duration(minutes: 40));
  final departure =
      live || !planned.isAfter(now.add(const Duration(minutes: 5)))
          ? null
          : planned;

  final cache = route == null || live
      ? null
      : LeaveDriveCache(await SharedPreferences.getInstance());
  final cached = cache?.get(eventKey, start, now, route!);
  if (cached != null) return plan(drive: cached);

  final drive = await routes.routeDuration(
    origin: origin,
    destination: destination,
    intermediates: via,
    departureTime: departure,
  );
  if (drive != null) await cache?.put(eventKey, start, now, route!, drive);
  return plan(drive: drive);
});
