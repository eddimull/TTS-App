// Shared venue-picker widgets used by EventSubFormCard.
//
// Contains the full three-step flow:
//   1. VenueSearchSheet  — autocomplete list; pops with VenuePrediction
//                          OR a free-typed VenuePrediction when the user
//                          taps "Use '<name>' as venue".
//   2. VenueMapPickerScreen — full-screen interactive map; pops with
//                             VenueDetails.  Skipped on Linux.
//   3. VenuePreviewCard  — embedded ~140 px map thumbnail (or a plain icon
//                          on Linux/web when the map widget is not reliable)
//                          shown after a venue has been confirmed.
//
// geocodeAddress() is also exposed so callers can geocode a prediction's
// address before opening the map picker.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/venue_search_service.dart';
import 'package:tts_bandmate/core/config/app_config.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Max length for a free-typed venue name — matches the backend's
/// VARCHAR(255) venue_name column so an over-long name cannot be submitted.
const int _kMaxVenueNameLength = 255;

// ── Platform capability guard ─────────────────────────────────────────────────

/// True on platforms where [google_maps_flutter] renders correctly.
bool get _mapsSupported => kIsWeb || Platform.isAndroid || Platform.isIOS;

// ── Geocoding helper ──────────────────────────────────────────────────────────

/// Dedicated Dio for the public Google Geocoding API. Deliberately separate
/// from the app's api_client.dart Dio — different host, and no auth header
/// should be attached. Cached so repeated geocode calls don't re-create it.
final Dio _geocodeDio = Dio();

/// Returns the first geocoding result's [LatLng] from the Geocoding REST API,
/// or null if the request fails / returns no results.
///
/// Uses the same geocoding approach as the old single-event booking form at
/// commit 2c00abb — REST call via Dio, NOT Places Details [fetchPlace], which
/// was broken on web.
Future<LatLng?> geocodeAddress(String address) async {
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
    final results = response.data?['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;
    final location =
        (results.first as Map<String, dynamic>)['geometry']?['location']
            as Map<String, dynamic>?;
    if (location == null) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  } catch (_) {
    return null;
  }
}

// ── Venue search sheet ────────────────────────────────────────────────────────
//
// Presents a [CupertinoSearchTextField] and a flat results list.
// Tapping a result pops immediately with the selected [VenuePrediction].
//
// When the user types a name that returns no results (or on Linux where
// [NoOpVenueSearchService] always returns []), a "Use '<query>' as venue" row
// appears so the user can accept free-typed text.

class VenueSearchSheet extends StatefulWidget {
  const VenueSearchSheet({
    super.key,
    required this.initialText,
    required this.service,
  });

  final String initialText;
  final VenueSearchService service;

  @override
  State<VenueSearchSheet> createState() => _VenueSearchSheetState();
}

class _VenueSearchSheetState extends State<VenueSearchSheet> {
  late final TextEditingController _query;
  List<VenuePrediction> _predictions = [];
  bool _searching = false;
  Timer? _debounce;

  /// The query text the last search ran for. Used to skip redundant searches
  /// when the controller listener fires on a cursor move rather than an edit.
  String? _lastSearchedText;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialText);
    _query.addListener(_onQueryChanged);
    if (widget.initialText.isNotEmpty) {
      _search();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    // The controller listener also fires on selection/cursor changes; skip
    // scheduling a search when the text itself has not changed.
    if (_query.text == _lastSearchedText) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    if (!mounted) return;
    final text = _query.text;
    _lastSearchedText = text;
    // An empty/whitespace query has nothing to look up — clear results
    // without hitting the service.
    if (text.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await widget.service.search(text);
    if (!mounted) return;
    setState(() {
      _predictions = results;
      _searching = false;
    });
  }

  void _select(VenuePrediction prediction) {
    Navigator.of(context).pop(prediction);
  }

  /// Accepts whatever the user has typed as a free-text venue name.
  /// Returns a synthetic [VenuePrediction] with an empty placeId and address.
  /// The name is clamped to [_kMaxVenueNameLength] so it cannot exceed the
  /// backend's venue_name column.
  void _acceptFreeText() {
    var name = _query.text.trim();
    if (name.isEmpty) return;
    if (name.length > _kMaxVenueNameLength) {
      name = name.substring(0, _kMaxVenueNameLength);
    }
    Navigator.of(context).pop(
      VenuePrediction(placeId: '', name: name, address: ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queryText = _query.text.trim();
    // Show the free-text option whenever the query is non-empty.
    // On Linux (NoOp service) this is the primary means of input.
    final showFreeText = queryText.isNotEmpty;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Select Venue'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
      child: Column(
        children: [
          // Search bar.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: CupertinoSearchTextField(
              controller: _query,
              placeholder: 'Venue name or address',
              autofocus: true,
            ),
          ),

          // Results list.
          Expanded(
            child: _searching
                ? const Center(child: CupertinoActivityIndicator())
                : ListView(
                    children: [
                      if (_predictions.isEmpty && !showFreeText)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 48),
                          child: Text(
                            'Start typing to search for a venue',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.secondaryText,
                            ),
                          ),
                        ),

                      // Autocomplete predictions.
                      ...List.generate(_predictions.length, (i) {
                        final p = _predictions[i];
                        return Column(
                          children: [
                            _ResultRow(
                              prediction: p,
                              onTap: () => _select(p),
                            ),
                            if (i < _predictions.length - 1)
                              Container(
                                height: 0.5,
                                margin: const EdgeInsets.only(left: 54),
                                color: CupertinoColors.separator
                                    .resolveFrom(context),
                              ),
                          ],
                        );
                      }),

                      // Free-text acceptance row — always below autocomplete
                      // results so the user can fall back to it any time.
                      if (showFreeText) ...[
                        if (_predictions.isNotEmpty)
                          Container(
                            height: 0.5,
                            color:
                                CupertinoColors.separator.resolveFrom(context),
                          ),
                        _FreeTextRow(
                          query: queryText,
                          onTap: _acceptFreeText,
                        ),
                      ],

                      // "No results" caption when there are no predictions and
                      // the user has typed something (the free-text row is shown
                      // but a hint helps orient the user).
                      if (_predictions.isEmpty && showFreeText)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(54, 4, 16, 8),
                          child: Text(
                            'No autocomplete results',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.tertiaryText,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Single search result row ──────────────────────────────────────────────────

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.prediction,
    required this.onTap,
  });

  final VenuePrediction prediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${prediction.name}, ${prediction.address}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.map_pin,
                size: 20,
                color: context.tertiaryText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prediction.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.primaryText,
                      ),
                    ),
                    if (prediction.address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        prediction.address,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: context.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Free-text acceptance row ──────────────────────────────────────────────────
//
// Shown when the user has typed something. Tapping it accepts the raw query
// as the venue name without going through autocomplete. This is the primary
// path on Linux (where NoOp search always returns []).

class _FreeTextRow extends StatelessWidget {
  const _FreeTextRow({
    required this.query,
    required this.onTap,
  });

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Use $query as venue name',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.pencil,
                size: 20,
                color: CupertinoColors.activeBlue.resolveFrom(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 15,
                      color: context.primaryText,
                    ),
                    children: [
                      const TextSpan(text: 'Use '),
                      TextSpan(
                        text: '"$query"',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const TextSpan(text: ' as venue name'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Full-screen map picker ────────────────────────────────────────────────────
//
// Shown after a venue is selected in the search sheet. The user can drag the
// red marker to fine-tune the pin location. Tapping "Confirm Location" pops
// with the final [VenueDetails] including the marker's coordinates.

class VenueMapPickerScreen extends StatefulWidget {
  const VenueMapPickerScreen({
    super.key,
    required this.venueName,
    required this.venueAddress,
    required this.initialPosition,
  });

  final String venueName;
  final String venueAddress;

  /// Geocoded starting position. Null when geocoding failed — the map will
  /// open at a world-level zoom and the user can pan to the correct location.
  final LatLng? initialPosition;

  @override
  State<VenueMapPickerScreen> createState() => _VenueMapPickerScreenState();
}

class _VenueMapPickerScreenState extends State<VenueMapPickerScreen> {
  // Falls back to a central world position if geocoding returned nothing.
  static const _worldCenter = LatLng(20.0, 0.0);

  late LatLng _markerPosition;

  @override
  void initState() {
    super.initState();
    _markerPosition = widget.initialPosition ?? _worldCenter;
  }

  void _onMarkerDragEnd(LatLng position) {
    setState(() => _markerPosition = position);
  }

  void _confirm() {
    Navigator.of(context).pop(VenueDetails(
      name: widget.venueName,
      address: widget.venueAddress,
      lat: _markerPosition.latitude,
      lng: _markerPosition.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Confirm Location'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
      child: Stack(
        children: [
          // Full-screen interactive map.
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _markerPosition,
                zoom: widget.initialPosition != null ? 15 : 2,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('venue'),
                  position: _markerPosition,
                  draggable: true,
                  onDragEnd: _onMarkerDragEnd,
                ),
              },
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // Venue name chip overlaid at the top of the map.
          Positioned(
            top: 8,
            left: 16,
            right: 16,
            child: _VenueNameChip(
              name: widget.venueName,
              address: widget.venueAddress,
            ),
          ),

          // "Confirm Location" button anchored at the bottom.
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPadding + 16,
            child: Semantics(
              label: 'Confirm venue location',
              child: CupertinoButton.filled(
                onPressed: _confirm,
                child: const Text(
                  'Confirm Location',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Venue name chip overlay on the map picker ─────────────────────────────────

class _VenueNameChip extends StatelessWidget {
  const _VenueNameChip({required this.name, required this.address});

  final String name;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground
            .resolveFrom(context)
            .withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.primaryText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              address,
              style: TextStyle(
                fontSize: 13,
                color: context.secondaryText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Drag the marker to adjust the pin.',
            style: TextStyle(
              fontSize: 12,
              color: context.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Venue preview card (shown in the event card after selection) ──────────────
//
// Shows the venue name + address plus either a live/static [GoogleMap] thumbnail
// (on supported platforms when lat/lng are known) or a [_MapPinPlaceholder]
// icon.  Always includes Change and Clear affordances.

class VenuePreviewCard extends StatelessWidget {
  const VenuePreviewCard({
    super.key,
    required this.venueName,
    required this.venueAddress,
    required this.lat,
    required this.lng,
    required this.onOpenMaps,
    this.onChange,
    this.onClear,
    this.readOnly = false,
  });

  final String venueName;
  final String venueAddress;
  final double? lat;
  final double? lng;
  final VoidCallback onOpenMaps;
  final VoidCallback? onChange;
  final VoidCallback? onClear;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final hasCoords = lat != null && lng != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map thumbnail — only on platforms where google_maps_flutter renders.
          if (_mapsSupported && hasCoords)
            _LiveMapThumbnail(lat: lat!, lng: lng!)
          else
            // Linux / web without reliable map support, or no coordinates yet.
            const _MapPinPlaceholder(),

          // Venue info + action row.
          Container(
            color: CupertinoColors.secondarySystemGroupedBackground
                .resolveFrom(context),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venueName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.primaryText,
                        ),
                      ),
                      if (venueAddress.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          venueAddress,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.secondaryText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Action buttons: open in Maps, change, clear.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: 'Open venue in Maps',
                      child: CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        onPressed: onOpenMaps,
                        child: Icon(
                          CupertinoIcons.map,
                          size: 20,
                          color:
                              CupertinoColors.activeBlue.resolveFrom(context),
                        ),
                      ),
                    ),
                    if (!readOnly) ...[
                      Semantics(
                        label: 'Change venue',
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: onChange,
                          child: Icon(
                            CupertinoIcons.pencil,
                            size: 20,
                            color:
                                CupertinoColors.activeBlue.resolveFrom(context),
                          ),
                        ),
                      ),
                      Semantics(
                        label: 'Clear venue',
                        child: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: onClear,
                          child: Icon(
                            CupertinoIcons.xmark_circle,
                            size: 20,
                            color: context.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live map thumbnail ────────────────────────────────────────────────────────

class _LiveMapThumbnail extends StatelessWidget {
  const _LiveMapThumbnail({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final position = LatLng(lat, lng);
    return SizedBox(
      height: 140,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: position, zoom: 15),
        markers: {
          Marker(markerId: const MarkerId('venue'), position: position),
        },
        // Disable all gestures — this is a read-only thumbnail.
        zoomGesturesEnabled: false,
        scrollGesturesEnabled: false,
        tiltGesturesEnabled: false,
        rotateGesturesEnabled: false,
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        // liteModeEnabled is Android-only; reduces GPU overhead for static views.
        liteModeEnabled: !kIsWeb && Platform.isAndroid,
      ),
    );
  }
}

// ── Map-pin icon placeholder ──────────────────────────────────────────────────
//
// Shown on Linux (no google_maps_flutter) or when coordinates are unavailable
// (free-typed venue name with no geocoded position).

class _MapPinPlaceholder extends StatelessWidget {
  const _MapPinPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      color: CupertinoColors.systemGrey5.resolveFrom(context),
      child: Center(
        child: Icon(
          CupertinoIcons.map_pin_ellipse,
          size: 36,
          color: context.tertiaryText,
        ),
      ),
    );
  }
}
