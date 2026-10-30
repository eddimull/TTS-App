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

/// A route waypoint: either coordinates or an address Google resolves itself.
class RoutePlace {
  const RoutePlace.point(GeoPoint this.point) : address = null;
  const RoutePlace.address(String this.address) : point = null;

  final GeoPoint? point;
  final String? address;

  Map<String, dynamic> toJson() => point != null
      ? {
          'location': {
            'latLng': {
              'latitude': point!.latitude,
              'longitude': point!.longitude,
            }
          }
        }
      : {'address': address};
}

/// Request body for `computeRoutes`. [departureTime] (future only) makes
/// Google use typical traffic for that day and hour; without it the route
/// uses live traffic from now. [intermediates] are stops on the way, and the
/// returned duration covers the whole trip.
Map<String, dynamic> buildRoutesRequest({
  required RoutePlace origin,
  required RoutePlace destination,
  List<RoutePlace> intermediates = const [],
  DateTime? departureTime,
}) =>
    {
      'origin': origin.toJson(),
      'destination': destination.toJson(),
      if (intermediates.isNotEmpty)
        'intermediates': [for (final p in intermediates) p.toJson()],
      'travelMode': 'DRIVE',
      'routingPreference': 'TRAFFIC_AWARE',
      if (departureTime != null)
        'departureTime': departureTime.toUtc().toIso8601String(),
    };

/// Computes traffic-aware driving time from a live origin to a venue address.
class RoutesClient {
  RoutesClient([Dio? dio]) : _dio = dio ?? Dio();
  final Dio _dio;

  static const _endpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Driving duration (traffic-aware) from [origin] to [destinationAddress],
  /// or null on any failure (missing key, geocode fail, route fail). See
  /// [buildRoutesRequest] for [departureTime] and [intermediates].
  Future<Duration?> driveDuration({
    required GeoPoint origin,
    required String destinationAddress,
    List<String> intermediates = const [],
    DateTime? departureTime,
  }) async {
    if (AppConfig.googlePlacesApiKey.isEmpty) return null;
    final dest = await geocodeAddress(destinationAddress);
    if (dest == null) return null;
    return routeDuration(
      origin: RoutePlace.point(origin),
      destination: RoutePlace.point(dest),
      intermediates: [for (final a in intermediates) RoutePlace.address(a)],
      departureTime: departureTime,
    );
  }

  /// Driving duration between any two places, or null on any failure.
  Future<Duration?> routeDuration({
    required RoutePlace origin,
    required RoutePlace destination,
    List<RoutePlace> intermediates = const [],
    DateTime? departureTime,
  }) async {
    if (AppConfig.googlePlacesApiKey.isEmpty) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        options: Options(headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': AppConfig.googlePlacesApiKey,
          'X-Goog-FieldMask': 'routes.duration',
        }),
        data: buildRoutesRequest(
          origin: origin,
          destination: destination,
          intermediates: intermediates,
          departureTime: departureTime,
        ),
      );
      final data = response.data;
      if (data == null) return null;
      return parseRoutesDuration(data);
    } catch (_) {
      return null;
    }
  }
}
