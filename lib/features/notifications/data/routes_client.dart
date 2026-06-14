import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/geocoding.dart';

/// Parse a Google Routes API `computeRoutes` response into a [Duration].
/// The `duration` field is a protobuf-style seconds string (e.g. "2705s") or
/// an integer count of seconds. Null when absent or unparseable.
Duration? parseRoutesDuration(Map<String, dynamic> data) {
  final routes = data['routes'] as List<dynamic>?;
  if (routes == null || routes.isEmpty) return null;
  final raw = (routes.first as Map)['duration'];
  if (raw is num) return Duration(seconds: raw.round());
  if (raw is String) {
    final cleaned = raw.endsWith('s') ? raw.substring(0, raw.length - 1) : raw;
    final secs = int.tryParse(cleaned);
    if (secs != null) return Duration(seconds: secs);
  }
  return null;
}

/// Computes traffic-aware driving time from a live origin to a venue address.
class RoutesClient {
  RoutesClient([Dio? dio]) : _dio = dio ?? Dio();
  final Dio _dio;

  static const _endpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Driving duration (traffic-aware) from [origin] to [destinationAddress],
  /// or null on any failure (missing key, geocode fail, route fail).
  Future<Duration?> driveDuration({
    required GeoPoint origin,
    required String destinationAddress,
  }) async {
    if (AppConfig.googlePlacesApiKey.isEmpty) return null;
    final dest = await geocodeAddress(destinationAddress);
    if (dest == null) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': AppConfig.googlePlacesApiKey,
          'X-Goog-FieldMask': 'routes.duration',
        }),
        data: {
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              }
            }
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': dest.latitude,
                'longitude': dest.longitude,
              }
            }
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
        },
      );
      final data = response.data;
      if (data == null) return null;
      return parseRoutesDuration(data);
    } catch (_) {
      return null;
    }
  }
}
