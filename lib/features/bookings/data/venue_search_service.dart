import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tts_bandmate/core/config/app_config.dart';

class VenuePrediction {
  const VenuePrediction({
    required this.placeId,
    required this.name,
    required this.address,
  });

  final String placeId;
  final String name;
  final String address;
}

/// Venue details after the user has confirmed a location on the map picker.
/// [lat] and [lng] come from geocoding in the map picker, not from the Places
/// Details API — they will be null if the user skipped the map step (Linux).
class VenueDetails {
  const VenueDetails({
    required this.name,
    required this.address,
    this.lat,
    this.lng,
  });

  final String name;
  final String address;

  /// Null on Linux (no-op service) or if the map picker was not used.
  final double? lat;
  final double? lng;
}

abstract class VenueSearchService {
  Future<List<VenuePrediction>> search(String query);
}

// ── Google Places implementation ──────────────────────────────────────────────

class PlacesVenueSearchService implements VenueSearchService {
  PlacesVenueSearchService()
      : _sdk = FlutterGooglePlacesSdk(AppConfig.googlePlacesApiKey);

  final FlutterGooglePlacesSdk _sdk;

  @override
  Future<List<VenuePrediction>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final result = await _sdk.findAutocompletePredictions(
        query,
        placeTypesFilter: [PlaceTypeFilter.ESTABLISHMENT],
      );
      return result.predictions.map((p) {
        return VenuePrediction(
          placeId: p.placeId,
          name: p.primaryText,
          address: p.secondaryText,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

// ── No-op fallback (Linux desktop) ───────────────────────────────────────────

class NoOpVenueSearchService implements VenueSearchService {
  @override
  Future<List<VenuePrediction>> search(String query) async => [];
}

// ── Provider ──────────────────────────────────────────────────────────────────

final venueSearchServiceProvider = Provider<VenueSearchService>((ref) {
  final isLinux = !kIsWeb && Platform.isLinux;
  if (isLinux) return NoOpVenueSearchService();
  return PlacesVenueSearchService();
});
