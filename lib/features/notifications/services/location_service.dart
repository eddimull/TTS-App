import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/network/geocoding.dart';

/// What level of location access the user has granted.
enum LocationGrant { always, whileInUse, denied }

bool get _supported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Wraps geolocator: tiered permission + a single current-position read.
class LocationService {
  /// Request location permission, escalating toward "always". Returns the tier
  /// actually granted. No-op (denied) on unsupported platforms.
  Future<LocationGrant> ensurePermission() async {
    if (!_supported) return LocationGrant.denied;
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationGrant.denied;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    switch (perm) {
      case LocationPermission.always:
        return LocationGrant.always;
      case LocationPermission.whileInUse:
        return LocationGrant.whileInUse;
      case LocationPermission.denied:
      case LocationPermission.deniedForever:
      case LocationPermission.unableToDetermine:
        return LocationGrant.denied;
    }
  }

  /// Current position as a [GeoPoint], or null if unavailable.
  Future<GeoPoint?> current() async {
    if (!_supported) return null;
    try {
      final pos = await Geolocator.getCurrentPosition();
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Straight-line distance in meters between two points.
  double distanceMeters(GeoPoint a, GeoPoint b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
}
