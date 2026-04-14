---
name: Venue Map Picker — google_maps_flutter integration
description: Two-step venue selection flow: autocomplete sheet pops with VenuePrediction, form geocodes then pushes _VenueMapPickerScreen; Linux fallback skips map
type: project
---

The venue picker in `booking_form_screen.dart` was refactored (2026-03-31) from a static map tile + Places Details API approach to a live `google_maps_flutter` flow.

**Flow:**
1. `_VenueSearchSheet` pops immediately with a `VenuePrediction` on single tap — no highlight/details step, no bottom map pane.
2. `_BookingFormScreenState._openVenueSearch` geocodes the address using the Geocoding REST API (`maps.googleapis.com/maps/api/geocode/json`) via Dio.
3. `_VenueMapPickerScreen` (full-screen CupertinoPageScaffold) shows an interactive `GoogleMap` with a draggable red marker. Confirm button pops with `VenueDetails(name, address, lat, lng)`.
4. Back in the form, `_VenuePreviewCard` shows a `_LiveMapThumbnail` — a non-interactive `GoogleMap` (all gestures disabled, `liteModeEnabled: true` on Android).

**Platform guard:** `_mapsSupported` = `kIsWeb || Platform.isAndroid || Platform.isIOS`. On Linux, `_openVenueSearch` short-circuits after step 1 (accepts name/address only), and `_VenuePreviewCard` shows `_MapPinPlaceholder` (icon) instead of a map.

**`VenueSearchService`:** `fetchDetails` removed from interface and both implementations. `VenueDetails` retains `lat`/`lng` fields but they come from the map picker, not from Places Details API.

**Why:** The Places Details API `fetchPlace` call was broken on web due to the deprecated `openingHours` getter; replacing it with a geocode call + native map widget avoids the JS SDK compatibility issue entirely.

**web/index.html:** Maps JS API script added in `<head>` with the key from launch.json (`AIzaSyB4J4IA0Q09PZnEoL9YPR-_B7k4-AF-Tgg`). The openingHours shim block was removed.

**pubspec.yaml:** `google_maps_flutter: ^2.17.0` added; `dependency_overrides` block for `flutter_google_places_sdk_web` removed.
