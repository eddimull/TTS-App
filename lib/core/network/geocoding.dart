import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// A plain latitude/longitude pair, independent of any maps package so the
/// notifications layer need not depend on google_maps_flutter.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Dedicated Dio for the public Google Geocoding API — separate from the app's
/// authenticated api_client (different host, no Bearer token).
final Dio _geocodeDio = Dio();

/// Pure parse of a Geocoding REST response body into a [GeoPoint]. Null when
/// there are no results or the shape is unexpected.
GeoPoint? parseGeocodeResponse(Map<String, dynamic> data) {
  final results = data['results'] as List<dynamic>?;
  if (results == null || results.isEmpty) return null;
  final location = (results.first as Map<String, dynamic>)['geometry']
      ?['location'] as Map<String, dynamic>?;
  if (location == null) return null;
  final lat = (location['lat'] as num?)?.toDouble();
  final lng = (location['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;
  return GeoPoint(lat, lng);
}

/// Returns the first geocoding result's [GeoPoint], or null on any failure.
/// REST call via Dio (Places Details fetchPlace was broken on web).
Future<GeoPoint?> geocodeAddress(String address) async {
  if (address.trim().isEmpty || AppConfig.googlePlacesApiKey.isEmpty) {
    return null;
  }
  try {
    final response = await _geocodeDio.get<Map<String, dynamic>>(
      'https://maps.googleapis.com/maps/api/geocode/json',
      queryParameters: {
        'address': address,
        'key': AppConfig.googlePlacesApiKey,
      },
    );
    final data = response.data;
    if (data == null) return null;
    return parseGeocodeResponse(data);
  } catch (_) {
    return null;
  }
}
