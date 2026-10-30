import 'package:flutter/cupertino.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:tts_bandmate/features/bookings/widgets/venue_picker.dart'
    show geocodeAddress, VenuePreviewCard;
import 'package:url_launcher/url_launcher.dart';

// ── Venue card with map preview ───────────────────────────────────────────────

class VenueCard extends StatefulWidget {
  const VenueCard({super.key, required this.venueName, this.venueAddress});
  final String venueName;
  final String? venueAddress;

  @override
  State<VenueCard> createState() => _VenueCardState();
}

class _VenueCardState extends State<VenueCard> {
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _geocodeVenue();
  }

  @override
  void didUpdateWidget(VenueCard old) {
    super.didUpdateWidget(old);
    // The venue can change under an open event page (realtime edits).
    if (old.venueName != widget.venueName ||
        old.venueAddress != widget.venueAddress) {
      _lat = null;
      _lng = null;
      _geocodeVenue();
    }
  }

  Future<void> _geocodeVenue() async {
    final fullAddress = [
      widget.venueName,
      if (widget.venueAddress != null && widget.venueAddress!.isNotEmpty)
        widget.venueAddress!,
    ].join(', ');
    final position = await geocodeAddress(fullAddress);
    if (!mounted) return;
    setState(() {
      _lat = position?.latitude;
      _lng = position?.longitude;
    });
  }

  @override
  Widget build(BuildContext context) {
    return VenuePreviewCard(
      venueName: widget.venueName,
      venueAddress: widget.venueAddress ?? '',
      lat: _lat,
      lng: _lng,
      readOnly: true,
      onOpenMaps: () => openVenueInMaps(
        context: context,
        venueName: widget.venueName,
        venueAddress: widget.venueAddress,
      ),
    );
  }
}

// ── Open-in-Maps helper ───────────────────────────────────────────────────────
//
// Geocodes the venue's full address (name + address) into coordinates, then
// hands them to [MapLauncher.showMarker]. The native iOS Apple Maps path of
// map_launcher ignores `extraParams` and pins the marker at whatever Coords
// it's given — so passing Coords(0, 0) lands the user at null island. We
// MUST resolve to real coords before launching.
//
// If geocoding fails (no network, missing API key, ambiguous address) we
// fall back to Google's documented universal Maps URL, which performs an
// address-text search and works reliably on both iOS and Android.

Future<void> openVenueInMaps({
  required BuildContext context,
  required String venueName,
  required String? venueAddress,
  bool directions = false,
}) async {
  final fullAddress = [
    venueName,
    if (venueAddress != null && venueAddress.isNotEmpty) venueAddress,
  ].join(', ');

  final position = await geocodeAddress(fullAddress);
  if (!context.mounted) return;

  // No coords — fall back to a search-by-address universal URL.
  if (position == null) {
    final searchUri = _webMapsUri(fullAddress, directions: directions);
    if (await canLaunchUrl(searchUri)) {
      await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  final coords = Coords(position.latitude, position.longitude);
  final availableMaps = await MapLauncher.installedMaps;
  if (!context.mounted) return;

  // No native maps installed (rare on iOS/Android) — fall back to web search.
  if (availableMaps.isEmpty) {
    final searchUri = _webMapsUri(fullAddress, directions: directions);
    if (await canLaunchUrl(searchUri)) {
      await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    }
    return;
  }

  if (availableMaps.length == 1) {
    await _show(availableMaps.first, coords, venueName, directions);
    return;
  }

  // Multiple map apps — let the user pick.
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      actions: [
        for (final map in availableMaps)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _show(map, coords, venueName, directions);
            },
            child: Text(map.mapName),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}

Future<void> _show(
        AvailableMap map, Coords coords, String venueName, bool directions) =>
    directions
        ? map.showDirections(destination: coords, destinationTitle: venueName)
        : map.showMarker(coords: coords, title: venueName);

/// Google's universal Maps URL: an address search, or directions to it.
Uri _webMapsUri(String address, {required bool directions}) => Uri.parse(
      directions
          ? 'https://www.google.com/maps/dir/?api=1'
              '&destination=${Uri.encodeComponent(address)}'
          : 'https://www.google.com/maps/search/?api=1'
              '&query=${Uri.encodeComponent(address)}',
    );
