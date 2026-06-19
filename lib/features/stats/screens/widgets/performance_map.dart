import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../data/models/user_stats.dart';

/// Full-width 300 px map showing a marker for each geocoded performance location.
/// Falls back to a placeholder on Linux where google_maps_flutter is unavailable.
class PerformanceMap extends StatelessWidget {
  const PerformanceMap({super.key, required this.locations});

  /// Pre-filtered to only include locations where [hasCoordinates] is true.
  final List<PerformanceLocation> locations;

  bool get _mapsSupported =>
      kIsWeb || Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    if (!_mapsSupported) {
      return const _MapUnsupportedPlaceholder();
    }

    final markers = locations
        .where((l) => l.hasCoordinates)
        .map(
          (l) => Marker(
            markerId: MarkerId('${l.lat}_${l.lng}_${l.title}'),
            position: LatLng(l.lat!, l.lng!),
            infoWindow: InfoWindow(
              title: l.venueName,
              snippet: l.venueAddress,
            ),
          ),
        )
        .toSet();

    final center = _averageCenter(locations);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 300,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: center,
              // Zoom out enough to see all markers — a fixed zoom works for
              // most datasets; users can pinch to refine.
              zoom: locations.length == 1 ? 12 : 5,
            ),
            markers: markers,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
          ),
        ),
      ),
    );
  }

  /// Simple arithmetic mean of all geocoded coordinates.
  LatLng _averageCenter(List<PerformanceLocation> locs) {
    final withCoords = locs.where((l) => l.hasCoordinates).toList();
    if (withCoords.isEmpty) return const LatLng(39.5, -98.35); // US center
    final avgLat =
        withCoords.map((l) => l.lat!).reduce((a, b) => a + b) / withCoords.length;
    final avgLng =
        withCoords.map((l) => l.lng!).reduce((a, b) => a + b) / withCoords.length;
    return LatLng(avgLat, avgLng);
  }
}

// ── Linux / unsupported platform fallback ─────────────────────────────────────

class _MapUnsupportedPlaceholder extends StatelessWidget {
  const _MapUnsupportedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey5.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(
            CupertinoIcons.map_pin_ellipse,
            size: 36,
            color: CupertinoColors.tertiaryLabel.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}
